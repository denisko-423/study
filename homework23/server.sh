#!/bin/bash

# Устанавливаем необходимые пакеты - bacula, mysql (mariadb) и утилиты для работы с SELinux
yum install -y bacula-director bacula-storage bacula-console mariadb-server setroubleshoot-server

# Запускаем mysql
systemctl enable --now mariadb

# Готовим БД для работы bacula
/usr/libexec/bacula/grant_mysql_privileges
/usr/libexec/bacula/create_mysql_database -u root
/usr/libexec/bacula/make_mysql_tables -u bacula
mysql -uroot -e "UPDATE mysql.user SET Password=PASSWORD('bacula') WHERE User='root';"
mysql -uroot -e "FLUSH PRIVILEGES;"
mysql -uroot -pbacula -e "DELETE FROM mysql.user WHERE User='';"
mysql -uroot -pbacula -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -uroot -pbacula -e "DROP DATABASE IF EXISTS test;"
mysql -uroot -pbacula -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
mysql -uroot -pbacula -e "FLUSH PRIVILEGES;"
mysql -uroot -pbacula -e "UPDATE mysql.user SET Password=PASSWORD('bacula') WHERE User='bacula';"
mysql -uroot -pbacula -e "FLUSH PRIVILEGES;"

# Меняем линк libbaccats.so на библиотеку MySQL
rm -f /etc/alternatives/libbaccats.so
ln -s /usr/lib64/libbaccats-mysql.so /etc/alternatives/libbaccats.so

# Создаем рабочие каталоги и назначаем им права доступа
mkdir -p /bacula/backup /bacula/restore
chown -R bacula:bacula /bacula
chmod -R 700 /bacula

# Правим контекст SELinux для рабочих каталогов
semanage fcontext -a -t bacula_store_t "/bacula(/.*)?" || :
restorecon -R -v /bacula

# Создаем конфиг Bacula Director
cat << 'EOF' | tee /etc/bacula/bacula-dir.conf
Director {
  Name = denisko-chef
  DirAddress = 127.0.0.1
  DIRport = 9101
  QueryFile = /etc/bacula/query.sql
  WorkingDirectory = /var/spool/bacula
  PidDirectory = /var/run
  Maximum Concurrent Jobs = 10
  Password = "denisko-dir"
  Messages = Standard
}

Job {
  Name = etc-Backup
  Type = Backup
  Level = Incremental
  Client = denisko-fd
  FileSet = etc-Set
  Schedule = HourlyCycle
  Storage = Storage
  Pool = FilePool
  Messages = Standard
  Write Bootstrap = /var/spool/bacula/%c.bsr
}

Job {
  Name = etc-Restore
  Type = Restore
  Client = denisko-fd
  FileSet = etc-Set
  Storage = Storage
  Pool = FilePool
  Messages = Standard
  Where = /bacula/restore
}

FileSet {
  Name = etc-Set
  Include {
    Options { signature = MD5 }
    File = /etc
  }
}

Schedule {
  Name = HourlyCycle
  Run = Full daily at 12:00
  Run = Incremental hourly at 0:01
  Run = Differential hourly at 0:06
  Run = Incremental hourly at 0:11
  Run = Incremental hourly at 0:21
  Run = Incremental hourly at 0:31
  Run = Differential hourly at 0:36
  Run = Incremental hourly at 0:41
  Run = Incremental hourly at 0:51
}

Client {
  Name = denisko-fd
  Address = 192.168.10.20
  FDPort = 9102
  Catalog = etcCatalog
  Password = "denisko-fd"
  File Retention = 30 days
  Job Retention = 6 months
  AutoPrune = yes
}

Catalog {
  Name = etcCatalog
  dbname = "bacula"; dbuser = "bacula"; dbpassword = "bacula"
}

Storage {
  Name = Storage
  Address = 192.168.10.10
  SDPort = 9103
  Password = "denisko-sd"
  Device = FileStorage
  Media Type = File
}

Pool {
  Name = FilePool
  Pool Type = Backup
  Label Format = etc-
  Recycle = yes
  AutoPrune = yes
  Volume Retention = 365 days
  Maximum Volume Bytes = 50G
  Maximum Volumes = 100
}

Messages {
  Name = Standard
  console = all, !skipped, !saved
  append = "/var/log/bacula/bacula.log" = all, !skipped
  catalog = all
}
EOF

# Создаем конфиг Storage Daemon
cat << 'EOF' | tee /etc/bacula/bacula-sd.conf
Storage {
  Name = denisko-sd
  SDAddress = 192.168.10.10
  SDPort = 9103
  WorkingDirectory = /var/spool/bacula
  Pid Directory = /var/run
  Maximum Concurrent Jobs = 20
}

Director {
  Name = denisko-chef
  Password = "denisko-sd"
}

Device {
  Name = FileStorage
  Media Type = File
  Archive Device = /bacula/backup
  LabelMedia = yes
  Random Access = yes
  AutomaticMount = yes
  RemovableMedia = no
  AlwaysOpen = no
}

Messages {
  Name = Standard
  director = denisko-chef = all
}
EOF

# Создаем конфиг Bacula Console
cat << 'EOF' | tee /etc/bacula/bconsole.conf
Director {
  Name = denisko-chef
  DIRport = 9101
  Address = 127.0.0.1
  Password = "denisko-dir"
}
EOF

# Запускаем сервисы
systemctl enable --now bacula-sd
systemctl enable --now bacula-dir

