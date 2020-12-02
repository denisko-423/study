#!/bin/bash

set -eux

# Установка zfs
yum install -y yum-utils
yum -y install http://download.zfsonlinux.org/epel/zfs-release.el8_2.noarch.rpm
gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
yum-config-manager --enable zfs-kmod
yum-config-manager --disable zfs
yum install -y zfs

# Загрузка zfs
modprobe zfs

# Автозагрузка zfs при старте ОС
cat << EOF | tee -a /etc/modules
zfs
EOF


