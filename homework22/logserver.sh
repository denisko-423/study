#!/bin/bash

# Устанавливаем пакет централизованного сбора логов по сети journald
yum -y install systemd-journal-gateway

# Создаем каталог для собираемых логов и назначаем ему необходимые права доступа
mkdir -p /var/log/journal/remote/
chown systemd-journal-remote:systemd-journal-remote /var/log/journal/remote

# Генерируем сертификаты для обмена по протоколу HTTPS
mkdir -p /etc/ssl/{private,certs,ca}
openssl genrsa -out /etc/ssl/ca/trusted.key 4096
openssl req -x509 -new -nodes -key /etc/ssl/ca/trusted.key -sha256 -days 1825 -out /etc/ssl/ca/trusted.pem -subj "/C=RU/ST=Vlad/L=Vlad/O=Vlad/OU=Vlad/CN=server"
openssl genrsa -out /etc/ssl/private/journal-remote.pem 2048
openssl req -new -key /etc/ssl/private/journal-remote.pem -out /etc/ssl/certs/journal-remote.csr -subj "/C=RU/ST=Vlad/L=Vlad/O=Vlad/OU=Vlad/CN=logserver"
openssl x509 -req -in /etc/ssl/certs/journal-remote.csr -CA /etc/ssl/ca/trusted.pem -CAkey /etc/ssl/ca/trusted.key -CAcreateserial -out /etc/ssl/certs/journal-remote.pem -days 1825 -sha256

# Правим конфиг сервиса sshd для авторизации по паролю, т.к. в дальнейшем
# потребуется скопировать сертификаты СА на удаленный сервер
# для генерации на нем собственных сертификатов
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd

# В конфиге сервиса приема логов с удаленных систем
# есть все необходимое, раскомментируем опции.
# Назначение опций:
# Seal=false - не подписывать собираемые логи сертификатом сервера.
# SplitMode=host - вести отдельный файл лога для каждого удаленного сервера.
# Остальные опции - сертификаты для сетевого взаимодействия по HTTPS.
sed -i 's/# //g' /etc/systemd/journal-remote.conf

# Чтобы сокет systemd-journal-remote.socket, через который ведет обмен
# сервис systemd-journal-remote.service, автоматически открывался
# и закрывался вместе с сервисом, в секцию сокета [Unit] необходимо
# добавить параметр PartOf=
cat << 'EOF' | tee /usr/lib/systemd/system/systemd-journal-remote.socket
[Unit]
Description=Journal Remote Sink Socket
PartOf=systemd-journal-remote.service
[Socket]
ListenStream=19532
[Install]
WantedBy=sockets.target
EOF

# Запускаем сервис systemd-journal-remote.service
systemctl daemon-reload
systemctl enable --now systemd-journal-remote.service

# Сервис приема логов работает в пассивном режиме,
# т.е. ожидает поступления данных с удаленных серверов.

# Теперь можно войти на сервер сбора логов logserver
# и наблюдать за поступлением записей с удаленной системы
# командой [sudo] journalctl -fD /var/log/journal/remote

