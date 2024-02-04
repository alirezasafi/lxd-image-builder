#!/bin/bash

current_dir="$(dirname "$0")"
source $current_dir/lxd-builder-tools.sh

# Build ubuntu-xenial LXD image
ARG APP_VERSION
ARG IMAGE_NAME=ubuntu-xenial-image-$APP_VERSION
ARG CONTAINER_NAME=ubuntu-xenial

FROM xenial:minbase

RUN "printf 'deb http://archive.ubuntu.com/ubuntu xenial main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu xenial-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu xenial-security main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu xenial-backports main restricted universe multiverse\n' > /etc/apt/sources.list"

RUN "apt-get update"
RUN "apt --allow-unauthenticated -qy install wget"

# install buildtime dependecy packages.
RUN "apt update --allow-insecure-repositories"
RUN "apt -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confnew' upgrade --allow-unauthenticated -qy"
RUN "apt --allow-unauthenticated -qy install dbus dbus-user-session systemd libsystemd-dev \
      ifupdown isc-dhcp-client iproute2 netbase net-tools udev \
      tar vim bash-completion htop"

RUN "printf 'auto eth0
iface eth0 inet dhcp
' > /etc/network/interface"

# Download runtime dependency packages.
# These packages needs daemon to install.
# 'RUN' commands executed in chroot and daemon isn't started in chroot.
RUN "apt --allow-unauthenticated -qy install redis-server --download-only"

ADD $current_dir/copy-necessary-libraries.sh /root/copy-necessary-libraries.sh

# Add libraries.
ADD $current_dir/libs/ /root/libs/

IMPORT $IMAGE_NAME
LAUNCH $IMAGE_NAME $CONTAINER_NAME

# 'EXEC' commands executed in running container and daemon is started.
# Install and Start redis-server
EXEC $CONTAINER_NAME "systemctl daemon-reload"
EXEC $CONTAINER_NAME "apt-get --allow-unauthenticated -qy install redis-server"
EXEC $CONTAINER_NAME "systemctl enable /lib/systemd/system/redis-server.service"
EXEC $CONTAINER_NAME "systemctl start redis-server"

# Export image from container
PUBLISH $CONTAINER_NAME $IMAGE_NAME

# Export image to tar file
EXPORT $IMAGE_NAME