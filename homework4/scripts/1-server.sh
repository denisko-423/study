#!/bin/bash

set -eux

echo Устанавливаем пакет для работы с NFS
sudo yum install -y nfs-utils

echo Включаем автозапуск, стартуем и проверяем состояние сервисов
sudo systemctl enable --now rpcbind
sudo systemctl -l status rpcbind
sudo systemctl enable --now nfs-server
sudo systemctl -l status nfs-server
sudo systemctl enable --now rpc-statd
sudo systemctl -l status rpc-statd
sudo systemctl enable --now nfs-idmapd
sudo systemctl -l status nfs-idmapd
sudo systemctl enable --now firewalld
sudo systemctl -l status firewalld

echo Настраиваем firewall на работу с NFS
sudo firewall-cmd --permanent --add-service={nfs3,mountd,rpc-bind}
sudo firewall-cmd --reload
sudo firewall-cmd --list-all

echo Создаем экспортируемый каталог, назначаем права
sudo mkdir -p /export/netfolder
sudo chmod 0777 /export/netfolder

echo Прописываем экспортируемый каталог в конфиг-файле
sudo echo '/export/netfolder  192.168.10.0/24(rw,async)' > /etc/exports

echo Применяем изменения
sudo exportfs -ra

echo Параметры экспортированных каталогов
cat /var/lib/nfs/etab

