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
sudo mkdir /nfs
sudo chmod 0777 /nfs

echo Монтируем экспортированный каталог с сервера: версия NFSv3, протокол UDP
sudo mount.nfs -vv nfs-server:/export/netfolder /nfs -o nfsvers=3,proto=udp,soft

echo Создаем в NFS-каталоге файл file1M размером 1МБ, сбрасываем на диск буфер ФС
dd if=/dev/zero of=/nfs/file1M bs=1K count=1024
sync

echo Убеждаемся, что файл появился в примонтированном NFS-каталоге
ls -al /nfs

echo Чтение файла на клиенте
dd if=/nfs/file1M of=/dev/null

echo По окончании работы на клиенте размонтируем NFS-каталог
sudo umount /nfs

