#!/bin/bash

# Устанавливаем необходимые пакеты:
# централизованный сбор логов по сети (systemd-journal-gateway)
# утилита авторизации по паролю в ssh-сессии (sshpass)
# плагин сервиса auditd для пересылки записей аудита в syslog (audispd-plugins)
# репозиторий nginx (epel-release)
yum -y install systemd-journal-gateway sshpass audispd-plugins epel-release

# Устанавливаем из подключенного репозитория nginx
yum -y install nginx

# Прописываем адрес и имя сервера централизованного сбора логов
echo "192.168.10.10 logserver" >> /etc/hosts

# Правим конфиг сервиса sshd для авторизации по паролю
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd

# Создаем каталоги для сертификатов
mkdir -p /etc/ssl/{private,certs,ca}

# Копируем сертификаты СА с сервера централизованного сбора логов
sshpass -p "vagrant" scp -o StrictHostKeyChecking=no vagrant@logserver:/etc/ssl/ca/trusted.?e? /etc/ssl/ca/

# Генерируем сертификаты веб-сервера для пересылки его логов
# на централизованный сервер по HTTPS
openssl genrsa -out /etc/ssl/private/journal-upload.pem 2048
openssl req -new -key /etc/ssl/private/journal-upload.pem -out /etc/ssl/certs/journal-upload.csr -subj "/C=RU/ST=Vlad/L=Vlad/O=Vlad/OU=Vlad/CN=webserver"
openssl x509 -req -in /etc/ssl/certs/journal-upload.csr -CA /etc/ssl/ca/trusted.pem -CAkey /etc/ssl/ca/trusted.key -CAcreateserial -out /etc/ssl/certs/journal-upload.pem -days 1825 -sha256

# Правим конфиг сервиса отправки логов systemd-journal-upload.service.
# Опцией URL задается адрес сервера сбора логов.
# Остальные опции - сертификаты для сетевого взаимодействия по HTTPS.
cat << 'EOF' | tee /etc/systemd/journal-upload.conf
[Upload]
URL=https://logserver:19532
ServerKeyFile=/etc/ssl/private/journal-upload.pem
ServerCertificateFile=/etc/ssl/certs/journal-upload.pem
TrustedCertificateFile=/etc/ssl/ca/trusted.pem
EOF

# Создаем минимально необходимый конфиг nginx.
# Лог подключений access_log полностью перенаправляется в syslog.
# Лог ошибок сохраняется локально и дублируется в syslog.
cat << 'EOF' | tee /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
pid /run/nginx.pid;
events {worker_connections 1024;}
http {
    server {
        listen 80 default_server;
        server_name main;
        access_log syslog:server=unix:/dev/log;
        error_log  syslog:server=unix:/dev/log;
        error_log  /var/log/nginx/error.log;
        root /usr/share/nginx/html;
        location / {}
        error_page 404 /404.html;
        location = /404.html {}
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {}
    }
}
EOF

# Запускаем сервисы
systemctl daemon-reload
systemctl enable --now systemd-journal-upload.service
systemctl enable --now nginx

# Включаем модуль сервиса auditd для пересылки записей аудита в syslog
sed -i 's/active = no/active = yes/' /etc/audisp/plugins.d/syslog.conf

# Создаем правило аудита для регистрации событий в каталоге конфигов nginx
# (появление/удаление/изменение файлов, каталогов и их атрибутов)
echo '-w /etc/nginx/ -p wa -k nginx_changes' > /etc/audit/rules.d/nginx.rules

# Перезапускаем сервис аудита для применения изменений
service auditd restart

# Теперь можно войти на веб-сервер и выполнить некоторые действия
# для проверки пересылки событий на централизованный сервер сбора логов:
# перезапуск сервисов, генерация системных сообщений,
# события аудита каталога конфигов nginx,
# открытие стартовой веб-страницы http://192.168.10.20,
# попытка открытия несуществующих веб-страниц, например http://192.168.10.20/aaa

