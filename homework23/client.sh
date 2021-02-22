#!/bin/bash

# Устанавливаем клиентский пакет File Daemon (FD)
yum install -y bacula-client

# Заполняем конфиг FD
cat << 'EOF' | tee /etc/bacula/bacula-fd.conf
Director {
  Name = denisko-chef
  Password = "denisko-fd"
}

FileDaemon {
  Name = denisko-fd
  FDport = 9102
  WorkingDirectory = /var/spool/bacula
  Pid Directory = /var/run
  Maximum Concurrent Jobs = 20
}

Messages {
  Name = Standard
  director = denisko-chef = all, !skipped, !restored
}
EOF

# Запускаем сервис FD
systemctl enable --now bacula-fd

