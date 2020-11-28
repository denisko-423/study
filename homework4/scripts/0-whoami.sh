#!/bin/sh

set -eux

whoami
uname -a
hostname -f
ip addr show dev eth1

