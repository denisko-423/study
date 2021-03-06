#!/bin/bash

# 65 MB
curl -O https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/images/pxeboot/initrd.img
# ~9 MB
curl -O https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/images/pxeboot/vmlinuz
# 1,7 GB
curl -O https://vault.centos.org/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso

# Установка необходимых пакетов
yum -y install epel-release
yum -y install dhcp tftp-server nfs-utils httpd syslinux-tftpboot.noarch

# Конфиг сервиса dhcpd
cat >/etc/dhcp/dhcpd.conf <<EOF
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

subnet 10.0.0.0 netmask 255.255.255.0 {
  #option routers 10.0.0.254;
  range 10.0.0.100 10.0.0.120;

  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server 10.0.0.20;

    if option architecture-type = 00:07 {
      filename "uefi/shim.efi";
      } else {
      filename "pxelinux/pxelinux.0";
    }
  }
}
EOF

mkdir -p /var/lib/tftpboot/pxelinux/pxelinux.cfg

# Меню PXE
cat >/var/lib/tftpboot/pxelinux/pxelinux.cfg/default <<EOF
default menu.c32
prompt 0
timeout 600

MENU TITLE PXE setup

LABEL linux-manual
  menu label ^Manual install CentOS 8.2 (nfs)
  kernel images/vmlinuz
  append initrd=images/initrd.img ip=dhcp inst.repo=nfs:10.0.0.20:/mnt/centos8-install
LABEL linux-auto
  menu label ^Auto install CentOS 8.2 (http)
  kernel images/vmlinuz
  append initrd=images/initrd.img ip=dhcp inst.ks=http://10.0.0.20/ks.cfg inst.repo=http://10.0.0.20/centos8-install/
LABEL local
  menu label ^Boot from local drive
  menu default
  kernel chain.c32
  append hd0 0
EOF

# Kick-файл для автоматической установки
cat > /var/www/html/ks.cfg <<EOF
ignoredisk --only-use=sda
autopart --type=lvm
clearpart --all --initlabel --drives=sda
graphical
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
network  --bootproto=dhcp --device=enp0s3 --ipv6=auto --activate
network  --bootproto=dhcp --device=enp0s8 --onboot=off --ipv6=auto --activate
network  --hostname=centos8host
rootpw --plaintext root
firstboot --enable
skipx
services --enabled="chronyd"
timezone America/New_York --isUtc
user --groups=wheel --name=val --password=val --plaintext --gecos="val"
reboot

%packages
@^minimal-environment
kexec-tools
%end

%addon com_redhat_kdump --enable --reserve-mb='auto'
%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
EOF

# Создание структуры TFTP и копирование файлов
mkdir -p /var/lib/tftpboot/pxelinux/images
cp -n /var/lib/tftpboot/{pxelinux.0,menu.c32,chain.c32,vesamenu.c32} /var/lib/tftpboot/pxelinux
cp -n /home/vagrant/{vmlinuz,initrd.img} /var/lib/tftpboot/pxelinux/images

# Монтирование iso-образа дистрибутива
mkdir -p /mnt/centos8-install
mount -t iso9660 /home/vagrant/CentOS-8.2.2004-x86_64-minimal.iso /mnt/centos8-install

# Автомонтирование дистрибутива при перезагрузке
echo '/home/vagrant/CentOS-8.2.2004-x86_64-minimal.iso /mnt/centos8-install iso9660 defaults 0 0' >> /etc/fstab

# Создание символической ссылки на дистрибутив для копирования по http
ln -s /mnt/centos8-install /var/www/html/

# Конфиг экспорта для nfs
echo '/mnt/centos8-install *(ro)' > /etc/exports

# Запуск и включение автозагрузки сервисов
systemctl enable --now dhcpd
systemctl enable --now tftp.service
systemctl enable --now nfs-server.service
systemctl enable --now httpd.service

