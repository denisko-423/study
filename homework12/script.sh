#!/bin/bash

title() {
  sleep $1
  for i in {1..5}; do echo; done
  echo ${2}
  echo ------------------------------------------------------------
}

for i in {1..5}; do echo; done
echo 'Часть 1. Мониторинг лога на предмет наличия ключевого слова'
echo ===========================================================

mkdir -p /opt/watchlog/
cd /opt/watchlog/

title 1 'Конфиг сервиса watchlog.service'

cat << 'EOF' | tee /etc/sysconfig/watchlog.conf
WHERE=/opt/watchlog/
LOG=watchlog.log
WORD="ALERT"
EOF

title 3 'Скрипт сервиса watchlog.service'
# Скрипт просматривает лог в поисках искомого слова.
# Строки, содержащие слово, выводятся в системный лог.
# Номер последней строки запоминается в файле watchlog.last.
# При следующем запуске просмотр лога начинается со
# следующей после запомненного номера строки.
cat << 'EOF' | tee watchlog.sh
#!/bin/bash

where=$1
log=${where}$2
word=$3
last=${where}watchlog.last

test -e $last && { read lastcount < $last; } || { lastcount=0; }
test -e $log && { currcount=`wc -l < $log`; } || { logger "Not found $log..."; exit 0; }
if [ ${currcount} -eq 0 ]
  then logger "$log is empty..."
elif [ ${currcount} -eq ${lastcount} ]
  then logger "$log is not changed..."
elif [ ${currcount} -lt ${lastcount} ]
  then
  grep $word $log | logger
  echo $currcount > $last
else 
  tail -n +$((${lastcount}+1)) $log | grep $word | logger
  echo $currcount > $last
fi
exit 0
EOF
chmod a+x watchlog.sh

title 3 'Юнит сервиса watchlog.service'

cat << 'EOF' | tee /etc/systemd/system/watchlog.service
[Unit]
Description=Watchlog service

[Service]
Type=simple
EnvironmentFile=/etc/sysconfig/watchlog.conf
ExecStart=/opt/watchlog/watchlog.sh $WHERE $LOG $WORD
EOF

title 3 'Юнит таймера сервиса watchlog.service'
# Опция OnUnitActiveSec задает периодичность запуска
# управляемого таймером юнита (Unit=), при этом
# отсчет времени ведется с момента последнего запуска
# (или завершения, толком не разобрался) юнита
# watchlog.service. Так как watchlog.service ни разу
# не запускался, то таймер не работает.
# Для гарантированного первого запуска watchlog.service
# добавлена опция OnActiveSec, которая стартует
# управляемый сервис сразу (=0) при старте таймера.
cat << 'EOF' | tee /etc/systemd/system/watchlog.timer
[Unit]
Description=Timer for Watchlog service

[Timer]
OnActiveSec=0
OnUnitActiveSec=2
AccuracySec=0.1
Unit=watchlog.service
EOF

title 3 'Скрипт генератора лога'
# Генератор сделан для демонстрации работы анализатора.
# С периодичностью 0,1 секунды в лог выводятся строки,
# при этом каждая 30-я строка содержит искомое слово.
# Выводимые строки нумеруются. Скрипт запускается
# отдельным сервисом.
# Последняя команда скрипта kill "убивает" бесконечный
# вывод записей из системного лога tail -f.
cat << 'EOF' | tee loggenerator.sh
#!/bin/bash

count=1
while [ $count -le 90 ]
do
  if [ $(($count%30)) -ne 0 ]
    then echo $count  "Normal message" >> /opt/watchlog/watchlog.log
    else echo $count  "We have ALERT!" >> /opt/watchlog/watchlog.log
  fi
  count=$(($count+1))
  sleep 0.1
done
sleep 7
kill `pgrep tail`
EOF
chmod a+x loggenerator.sh

title 3 'Юнит сервиса генератора лога'

cat << 'EOF' | tee /etc/systemd/system/loggenerator.service
[Unit]
Description=Log generator

[Service]
Type=simple
ExecStart=/opt/watchlog/loggenerator.sh
EOF

title 3 'Запуск таймера сервиса watchlog.service и генератора лога'

systemctl start watchlog.timer
sleep 1.5
systemctl start loggenerator.service

title 1 'Результат выполнения'

tail -f /var/log/messages || :

sleep 5
for i in {1..5}; do echo; done
echo 'Часть 2. Unit-файл spawn-fcgi.service'
echo ===========================================================

title 1 'Установка необходимых пакетов'

yum install -y epel-release > /dev/null 2>&1
yum install -y spawn-fcgi php php-cli mod_fcgid httpd > /dev/null 2>&1

echo 'SOCKET=/var/run/php-fcgi.sock' >> /etc/sysconfig/spawn-fcgi
echo 'OPTIONS="-u apache -g apache -S -M 0600 -C 10 -F 1 -P /var/run/spawn-fcgi.pid -- /usr/bin/php-cgi"' >> /etc/sysconfig/spawn-fcgi

title 1 'Юнит сервиса spawn-fcgi.service'
# Команды в опциях ExecStartPre и ExecStopPost
# (удаление сокета перед запуском и после остановки сервиса)
# взяты из init-скрипта пакета.
# На мой взгляд, это самое существенное в скрипте,
# помимо собственно запуска и остановки программы.
# Опцию в строке запуска -s $SOCKET пришлось вынести
# отдельно из OPTIONS, т.к. раскрытие переменной внутри
# переменной не выполнялось, и сокет не создавался.
# Опция ExecStop не нужна, т.к. в init-скрипте
# процесс просто убивается (kill), что по умолчанию
# и так делает systemd.
cat << 'EOF' | tee /etc/systemd/system/spawn-fcgi.service
[Unit]
Description=My spawn-fcgi service
After=network.target

[Service]
Type=simple
Restart=no
KillMode=process
RemainAfterExit=yes
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/sysconfig/spawn-fcgi
ExecStartPre=/bin/bash -c '[ -n ${SOCKET} -a -S ${SOCKET} ] && rm -f ${SOCKET} || :'
ExecStart=/usr/bin/spawn-fcgi -s $SOCKET $OPTIONS
ExecStopPost=/bin/bash -c '[ -n ${SOCKET} -a -S ${SOCKET} ] && rm -f ${SOCKET} || :'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start spawn-fcgi

title 3 'Статус сервиса spawn-fcgi.service после запуска'
systemctl status spawn-fcgi

title 3 'Созданный сокет (php-fcgi.sock) и PID-файл (spawn-fcgi.pid)'
ls -l /run/*-fcgi.*

systemctl stop spawn-fcgi

title 3 'Статус сервиса spawn-fcgi.service после остановки'
systemctl status spawn-fcgi

title 3 'Сокет и PID-файл удалены'
ls -l /run/

sleep 5
for i in {1..5}; do echo; done
echo 'Часть 3. Несколько инстансов сервиса httpd'
echo ===========================================================

title 1 'Unit-файл сервиса с шаблоном'
# Шаблон %i присутствует в опции EnvironmentFile
cat << 'EOF' | tee /etc/systemd/system/httpd@.service
[Unit]
Description=The _instantiated_ Apache HTTP Server
After=network.target remote-fs.target nss-lookup.target
Documentation=man:httpd(8)
Documentation=man:apachectl(8)

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/httpd%i
ExecStart=/usr/sbin/httpd $OPTIONS -DFOREGROUND
ExecReload=/usr/sbin/httpd $OPTIONS -k graceful
ExecStop=/bin/kill -WINCH ${MAINPID}
KillSignal=SIGCONT
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

echo 'OPTIONS="-f conf/httpd.conf"' >> /etc/sysconfig/httpd
echo 'LANG=C' > /etc/sysconfig/httpdfirst
echo 'OPTIONS="-f conf/httpdfirst.conf"' >> /etc/sysconfig/httpdfirst
echo 'LANG=C' > /etc/sysconfig/httpdsecond
echo 'OPTIONS="-f conf/httpdsecond.conf"' >> /etc/sysconfig/httpdsecond
cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpdfirst.conf
cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpdsecond.conf
# Штатно сервис httpd слушает порт 80.
# Сервис httpdfirst настроен на порт 8080.
# Сервис httpdsecond настроен на порт 443.
echo 'PidFile "/var/run/httpd/httpd.pid"' >> /etc/httpd/conf/httpd.conf
sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpdfirst.conf
echo 'PidFile "/var/run/httpd/httpdfirst.pid"' >> /etc/httpd/conf/httpdfirst.conf
sed -i 's/Listen 80/Listen 443/' /etc/httpd/conf/httpdsecond.conf
echo 'PidFile "/var/run/httpd/httpdsecond.pid"' >> /etc/httpd/conf/httpdsecond.conf

systemctl start httpd
systemctl start httpd@first
systemctl start httpd@second

title 3 'Статус сервиса httpd'
systemctl status httpd

title 3 'Статус сервиса httpd@first'
systemctl status httpd@first

title 3 'Статус сервиса httpd@second'
systemctl status httpd@second

title 3 'Прослушиваемые сервисами порты'
ss -tnulp | grep httpd

