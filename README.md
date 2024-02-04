# LXD Image Builder Tool

## Introduction
LXD Image Builder Tool is an innovative command-line utility designed to simplify the process of creating and managing LXD (Linux Containers) images, specifically tailored for Ubuntu distributions. Mimicking the simplicity and efficiency of a Dockerfile for Docker, this tool introduces a declarative syntax allowing users to define and build custom LXD images with ease.

## Features
This tool supports a variety of commands (or functions) enabling a wide range of operations from image creation to exporting:
- **ARG**: Define variables to be passed at build-time.
- **FROM**: Bootstrap a Debian base system from archive.ubuntu.com.
- **RUN**: Execute commands within the chroot of the target system.
- **EXEC**: Execute commands directly in a running LXC container.
- **ADD**: Copy files or directories from the host to the destination path in the image.
- **IMPORT**: Compress the target Debian system into a tar file and import it with `metadata.yaml`.
- **LAUNCH**: Launch a container from an imported image.
- **PUBLISH**: Export an image from a running LXC container.
- **EXPORT**: Export an image to a compressed tar file.


## Usage
The LXD Image Builder Tool simplifies the creation and management of LXD images. Below is a step-by-step guide to using this tool, highlighted by a detailed example based on the sample file you've provided.

### Defining Your Image
Create a definition file (e.g., `lxd-image-template.sh`) and use the supported commands to define your image. Here's an example structure based on the sample file:

```bash
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
```

### Build Your Image
To build your image, execute the LXD Image Builder Tool with your definition file as an argument:

```bash
chmod +x lxd-image-template.sh
./lxd-image-template.sh
```

## Sample File

A sample file `lxd-image-template.sh` is included in the repository to help you get started. This template provides a comprehensive example of how to use each command supported by the tool. Refer to this file for detailed syntax and options.

## Note
Ensure that LXD is correctly installed and configured on your system before attempting to use this tool. For more detailed instructions and advanced usage, refer to the official LXD documentation.

```bash
apt-get install -qy lxd lxc
lxd init --auto