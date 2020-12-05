#!/bin/sh

set -eux

whoami
uname -a
hostname -f

cat >> /etc/yum.repos.d/otus.repo << EOF
[otus]
name=otus-linux
baseurl=http://192.168.10.10/repo
gpgcheck=0
enabled=1
EOF

# Без этих двух шагов (очистка и пересоздание кэша пакетов)
# в репозитории otus виден только nginx, percona-release отсутствует.
# Объяснения у меня нет.
yum clean all
yum makecache

yum list | grep otus
yum install -y percona-release

