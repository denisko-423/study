#!/bin/bash

set -eux

echo Устанавливаем пакет для работы с NFS
sudo yum install -y nfs-utils

echo Включаем автозагрузку и запускаем firewalld, на клиенте настройки не требуется
sudo systemctl enable --now firewalld
sudo systemctl -l status firewalld

echo Работа с сервером будеть проводиться по символическому имени nfs-server
sudo echo '192.168.10.10 nfs-server' >> /etc/hosts
ping -c 4 nfs-server

echo Создаем точку монтирования NFS, назначаем права
sudo mkdir /nfsfolder
sudo chmod 0777 /nfsfolder

echo Монтируем экспортированный каталог с сервера: версия NFSv3, протокол UDP
sudo mount.nfs -vv nfs-server:/export/netfolder /nfsfolder -o nfsvers=3,proto=udp,soft

echo Создаем в NFS-каталоге папку upload, в ней файл file1M размером 1МБ, сбрасываем на диск буфер ФС
# Дополнительное действие
mkdir /nfsfolder/upload
# of=/nfsfolder/file1M ---> of=/nfsfolder/upload/file1M
dd if=/dev/zero of=/nfsfolder/upload/file1M bs=1K count=1024
sync

echo Убеждаемся, что файл появился в папке upload
# /nfsfolder ---> /nfsfolder/upload
ls -al /nfsfolder/upload

echo Копирование файла на клиенте
# /nfsfolder/file1M ---> /nfsfolder/upload/file1M
cp /nfsfolder/upload/file1M .

echo Настройка автомонтирования каталога при старте
sudo touch /etc/systemd/system/nfsfolder.mount
cat << EOF | sudo tee /etc/systemd/system/nfsfolder.mount
[Unit]
  Description=Mount NFS Share
  Requires=network-online.target
  After=network-online.service

[Mount]
  What=nfs-server:/export/netfolder
  Where=/nfsfolder
  Options=nfsvers=3,proto=udp,soft
  Type=nfs

[Install]
  WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable nfsfolder.mount

echo Перезапускаем клиента
sudo shutdown -r now

