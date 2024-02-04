#!/bin/bash

CACHE_DIR="/tmp/lxd/.cache"
ENABLE_CACHE="ON"

set -e

##############################################
# compute the checksum of input argument.
# if the input is a directory or file, compute the checksum
# of the selected file(s) othervise
# considered as a string and compute checksum of it.
# Arguments:
#   target_value: input value (directory, file, string)
# Return value:
#   string value of checksum
# E.g:
#   command_checksum=$(__compute_checksum "some-string")
#   command_checksum=$(__compute_checksum "/root/binary-file")
#   command_checksum=$(__compute_checksum "/root/cache/")
##############################################
__compute_checksum() {
  local target_value=$1
  if [ -d "$target_value" ]; then
    find "$target_value" -type f -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}'
  elif [ -f "$target_value" ]; then
    md5sum "$target_value" | awk '{print $1}'
  else
    echo -n $1 "$1" | md5sum | awk '{print $1}'
  fi
}

##############################################
# check a container is running or not.
# Arguments:
#   container_name: name of the container
# Return value:
#   int value 0 or 1 (False or True)
# E.g:
#   container_is_running=$(__container_is_running "$container_name")
##############################################
__container_is_running() {
  local container_name=$1
  contaienr_status=$(lxc list --format json | jq -r ".[] | select(.name == \"$container_name\") | .status")
  [[ "$contaienr_status" = "Running" ]]; echo "$?"
}

##############################################
# this function defines a variable that users
# can pass at build-time to the builder with
# the <key>=<value> flag.
# it also set the key-value in arguments
# global dict variable and export them in host.
# Arguments:
#   key: key variable name
#   value: value of the key
# E.g:
#   ARG KEY_NAME=VALUE
##############################################
ARG() {
  local key
  local value
  IFS='=' read -r key value <<< "$1"
  build_arg=${arguments["$key"]}
  if [ -z $build_arg ]; then
	if [ -z $value ]; then
      echo "---> argument ($key) should not be blank!"
      exit 1
	fi
	export "$key=$value"
  else
  	export "$key=$build_arg"
  fi
}

##############################################
# bootstrap a debian base system
# from archive.ubuntu.com into a target
# (/tmp/lxd/<suite>-<variant>) directory.
# Arguments:
#   suite: release code name
#   variant: variant X of the bootstrap scripts.
#          supported variants: buildd, fakechroot,
#          scratchbox, minbase
# E.g:
#   FROM xenial:minbase
##############################################
FROM() {
  local suite
  local variant
  IFS=':' read -r suite variant <<< "$1"
  target=/tmp/lxd/$suite-$variant
  if [[ ! -d "$target" || "$ENABLE_CACHE" != "ON" ]]; then
    rm -rf "$target"
    echo "---> Pulling $suite:$variant to $target"
    debootstrap --variant=$variant $suite $target http://archive.ubuntu.com/ubuntu/
  fi
}

##############################################
# execute a command in chroot of the target system.
# Arguments:
#   command: the input command string
# E.g:
#   RUN "apt-get update"
##############################################
RUN() {
  local command="$1"
  local command_checksum
  local exit_code
  command_checksum=$(__compute_checksum "$command")
  if [[ ! -f $CACHE_DIR/$command_checksum || "$ENABLE_CACHE" != "ON" ]]; then
    echo "---> Running in ${command_checksum:0:8}"
    chroot $target /bin/bash <<END
    $command
END
    exit_code=$?
    echo "$command" > "$CACHE_DIR/$command_checksum"
    if [ "$exit_code" != "0" ]; then
      rm -f "$CACHE_DIR/$command_checksum"
      exit exit_code
    fi
    ENABLE_CACHE="OFF"
  else
    echo "---> Using cache: ${command_checksum:0:8}"
  fi
}

##############################################
# execute a command in running LXC container straightly.
# be sure that the container is in the running state.
# Arguments:
#   container_name: name of the container
#   command: the input command string
# E.g:
#   EXEC ubuntu-container "systemctl start redis-server"
##############################################
EXEC() {
  local container_name=$1
  local command=$2
  local command_checksum
  command_checksum=$(__compute_checksum "$command")
  if [[ ! -f $CACHE_DIR/$command_checksum || "$ENABLE_CACHE" != "ON" ]]; then
    container_is_running=$(__container_is_running "$container_name")
    if [ "$container_is_running" != "0" ]; then
      echo "container not running to execute command!"
      exit 1
    fi
    echo "---> Executing in ${command_checksum:0:8}"
    lxc exec $container_name -- bash -c "$command"
    exit_code=$?
    echo "$command" > "$CACHE_DIR/$command_checksum"
    if [ "$exit_code" != "0" ]; then
      rm -f "$CACHE_DIR/$command_checksum"
      exit exit_code
    fi
    ENABLE_CACHE="OFF"
  else
    echo "---> Using cache: ${command_checksum:0:8}"
  fi
}

##############################################
# copy the source path in host to the destination path
# in image.
# Arguments:
#   source: source path (file or directory)
#   destination: destination path (file or directory)
# E.g:
#   ADD /root/cache/ /root/cache/
#   ADD /root/binary-file /root/root/binary-file
##############################################
ADD() {
  local source=$1
  local destination=$2
  local source_checksum=$(__compute_checksum "$source")
  local destination_checksum=$(__compute_checksum "$target/$destination")
  if [[ "$source_checksum" != "$destination_checksum" || "$ENABLE_CACHE" != "ON" ]]; then
    echo "---> ADD $source to $destination"
    rm -rf $target$destination
    if [ -d $source ]; then
      mkdir -p $target$destination
      cp -rf $source/* $target$destination
    elif [ -f $source ]; then
      mkdir -p $(dirname "$target$destination")
      cp -rf $source $target$destination
    else
      echo "the source: $source does not exist!"
      exit 1
    fi
    ENABLE_CACHE="OFF"
  else
    echo "---> Using cache: ${source_checksum:0:8}"
  fi
}

##############################################
# this function compress target debian system
# in to a tar file and import it with metadata.yaml
# Arguments:
#   image_name: name of the LXC image to be imported
# E.g:
#   IMPORT ubuntu-image
##############################################
IMPORT() {
  local image_name=$1
  if [ "$ENABLE_CACHE" != "ON" ]; then
    echo "---> IMPORT TARGET IMAGE"
    lxc image delete $image_name > /dev/null 2>&1 || true
    tar -czf $CACHE_DIR/rootfs.tar.gz -C $target .
    tar -czf $CACHE_DIR/metadata.tar.gz -C $current_dir metadata.yaml
    lxc image import $CACHE_DIR/metadata.tar.gz $CACHE_DIR/rootfs.tar.gz --alias $image_name
    rm -rf $CACHE_DIR/metadata.tar.gz $CACHE_DIR/rootfs.tar.gz
  fi
}

##############################################
# launch a container from already imported image.
# Arguments:
#   image_name: name of the LXC image
#   container_name: name of the container to be launched
# E.g:
#   LAUNCH ubuntu-image ubuntu-container
##############################################
LAUNCH() {
  local image_name=$1
  local container_name=$2
  if [ "$ENABLE_CACHE" != "ON" ]; then
    lxc delete -f $container_name > /dev/null 2>&1 || true
    echo "---> LAUNCHE THE CONTAINER"
    lxc launch $image_name $container_name
  fi
}

##############################################
# export an image from running LXC container.
# Arguments:
#   container_name: name of the running container
#   image_name: name of the LXC image to be exported
# E.g:
#   PUBLISH ubuntu-container ubuntu-image
##############################################
PUBLISH() {
  local container_name=$1
  local image_name=$2
  if [ "$ENABLE_CACHE" != "ON" ]; then
    echo "---> PUBLISH CONTAINER"
    lxc image delete $image_name > /dev/null 2>&1 || true
    lxc stop -f $container_name > /dev/null 2>&1 || true
    lxc publish $container_name --alias $image_name
    lxc delete -f $ontainer_name > /dev/null 2>&1 || true
  fi
}

##############################################
# export an image to a compress tar file.
# this function create a tar file in current
# directory with name: <input-image-name>-image.tar.gz
# Arguments:
#   image_name: name of the LXC image
# E.g:
#   EXPORT ubuntu-image
##############################################
EXPORT() {
  local image_name=$1
  if [ "$ENABLE_CACHE" != "ON" ]; then
    echo "---> EXPORT IMAGE"
    lxc image export $image_name $image_name-image
    echo "---> image exported in $image_name-image.tar.gz"
  fi
}

declare -A arguments
for argument in "$@"; do
  case "$argument" in 
    "--no-cache")
      ENABLE_CACHE="OFF"
      rm -rf $CACHE_DIR
      ;;
    *)
      IFS='=' read -r KEY VALUE <<< "$argument"
      arguments["$KEY"]="$VALUE"
      export "$KEY=$VALUE"
      ;;
  esac
done
apt install debootstrap lxc lxd jq -qy > /dev/null 2>&1
mkdir -p $CACHE_DIR