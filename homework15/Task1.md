## Задание
Запустить nginx на нестандартном порту тремя разными способами:
- переключатели setsebool;
- добавление нестандартного порта в имеющийся тип;
- формирование и установка модуля SELinux.

## Подготовка стенда
Подключаем репозиторий EPEL и устанавливаем из него nginx:  
```
[root@nginx-and-selinux vagrant]# yum -y install epel-release
[root@nginx-and-selinux vagrant]# yum -y install nginx
```
После запуска (`systemctl start nginx`) сервис стандартно слушает порт 80:
```
[root@nginx-and-selinux vagrant]# ss -tupnl | grep nginx
tcp    LISTEN     0      128       *:80                    *:*                   users:(("nginx",pid=2802,fd=6),("nginx",pid=2801,fd=6))
tcp    LISTEN     0      128    [::]:80                 [::]:*                   users:(("nginx",pid=2802,fd=7),("nginx",pid=2801,fd=7))
```
Изменим в конфиге tcp-порт ipv4 на нестандартный 3080:
```
[root@nginx-and-selinux vagrant]# cat /etc/nginx/nginx.conf
...
        listen       3080 default_server;
...
```
После перезапуска сервис nginx ожидаемо не поднялся - SELinux не разрешил сервису доступ к нестандартному порту:
```
[root@nginx-and-selinux vagrant]# systemctl restart nginx
Job for nginx.service failed because the control process exited with error code. See "systemctl status nginx.service" and "journalctl -xe" for details.
```
Для работы с SELinux нужно установить инструментарий:
```
yum -y install setools-console policycoreutils-python setroubleshoot-server
```
Стенд готов к работе.

## Анализ ситуации
Для анализа записей в логе SELinux используем утилиту sealert, которая интересна тем, что предлагает несколько решений проблемы (если таковые существуют), при этом каждому решению присваивает баллы "уверенности". Чем больше баллов, тем более предпочтительным, с точки зрения утилиты, является решение:
```
[root@nginx-and-selinux vagrant]# sealert -a /var/log/audit/audit.log 
100% done
found 1 alerts in /var/log/audit/audit.log
--------------------------------------------------------------------------------

SELinux is preventing /usr/sbin/nginx from name_bind access on the tcp_socket port 3080.

*****  Plugin bind_ports (92.2 confidence) suggests   ************************

If you want to allow /usr/sbin/nginx to bind to network port 3080
Then you need to modify the port type.
Do
# semanage port -a -t PORT_TYPE -p tcp 3080
    where PORT_TYPE is one of the following: http_cache_port_t, http_port_t, jboss_management_port_t, jboss_messaging_port_t, ntop_port_t, puppet_port_t.

*****  Plugin catchall_boolean (7.83 confidence) suggests   ******************

If you want to allow nis to enabled
Then you must tell SELinux about this by enabling the 'nis_enabled' boolean.

Do
setsebool -P nis_enabled 1

*****  Plugin catchall (1.41 confidence) suggests   **************************

If you believe that nginx should be allowed name_bind access on the port 3080 tcp_socket by default.
Then you should report this as a bug.
You can generate a local policy module to allow this access.
Do
allow this access for now by executing:
# ausearch -c 'nginx' --raw | audit2allow -M my-nginx
# semodule -i my-nginx.pp


Additional Information:
Source Context                system_u:system_r:httpd_t:s0
Target Context                system_u:object_r:unreserved_port_t:s0
Target Objects                port 3080 [ tcp_socket ]
Source                        nginx
Source Path                   /usr/sbin/nginx
Port                          3080
Host                          <Unknown>
Source RPM Packages           nginx-1.16.1-3.el7.x86_64
Target RPM Packages           
Policy RPM                    selinux-policy-3.13.1-266.el7.noarch
Selinux Enabled               True
Policy Type                   targeted
Enforcing Mode                Enforcing
Host Name                     nginx-and-selinux
Platform                      Linux nginx-and-selinux 3.10.0-1127.el7.x86_64 #1
                              SMP Tue Mar 31 23:36:51 UTC 2020 x86_64 x86_64
Alert Count                   2
First Seen                    2021-01-24 03:48:43 UTC
Last Seen                     2021-01-24 03:49:20 UTC
Local ID                      8b345e85-e2f4-4ba2-8fae-9ffe58360aac

Raw Audit Messages
type=AVC msg=audit(1611460160.464:738): avc:  denied  { name_bind } for  pid=2830 comm="nginx" src=3080 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0


type=SYSCALL msg=audit(1611460160.464:738): arch=x86_64 syscall=bind success=no exit=EACCES a0=6 a1=55d9f685b200 a2=10 a3=7ffc0e462570 items=0 ppid=1 pid=2830 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm=nginx exe=/usr/sbin/nginx subj=system_u:system_r:httpd_t:s0 key=(null)

Hash: nginx,httpd_t,unreserved_port_t,tcp_socket,name_bind
```
Причина неработоспособности nginx - несоответствие контекстов процесса и порта. Контекст процесса - system\_u:system\_r:httpd\_t:s0 (домен httpd\_t), контекст порта - system\_u:object\_r:unreserved\_port\_t:s0 (тип unreserved\_port\_t). Так как домен процесса изменить невозможно (слишком много на него завязано), то остается изменить тип порта, либо разрешить SELinux взаимодействие этих типов.
Лучшим решением (92.2 балла из 100) утилита считает изменение типа порта, вторым по значимости (7.83 балла) использование переключателя, и как вариант (1.41 балла) компилирование и установку модуля политики.

## Изменение типа порта
Существующий тип порта 3080 - unreserved\_port\_t. Нужно изменить его тип, чтобы nginx смог с ним работать.  
Стандартно nginx использует порт 80. Очевидно, что в SELinux есть все необходимое для него. Тип порта 80 можно узнать командой:
```
[root@nginx-and-selinux vagrant]# seinfo --portcon=80
        portcon tcp 80 system_u:object_r:http_port_t:s0
        portcon tcp 1-511 system_u:object_r:reserved_port_t:s0
        portcon udp 1-511 system_u:object_r:reserved_port_t:s0
        portcon sctp 1-511 system_u:object_r:reserved_port_t:s0
```
Тип порта 80 - http\_port\_t. Его и назначим новому порту 3080.
Выполним предложенную утилитой команду, подставив в нее требуемый тип порта:
```
semanage port -a -t http\_port\_t -p tcp 3080
```
Теперь nginx запускается и работает нормально, новый порт прослушивается:
```
[root@nginx-and-selinux vagrant]# systemctl start nginx


[root@nginx-and-selinux vagrant]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
   Loaded: loaded (/usr/lib/systemd/system/nginx.service; disabled; vendor preset: disabled)
   Active: active (running) since Sun 2021-01-24 06:56:45 UTC; 7s ago
  Process: 23992 ExecStart=/usr/sbin/nginx (code=exited, status=0/SUCCESS)
  Process: 23989 ExecStartPre=/usr/sbin/nginx -t (code=exited, status=0/SUCCESS)
  Process: 23988 ExecStartPre=/usr/bin/rm -f /run/nginx.pid (code=exited, status=0/SUCCESS)
 Main PID: 23994 (nginx)
   CGroup: /system.slice/nginx.service
           ├─23994 nginx: master process /usr/sbin/nginx
           └─23995 nginx: worker process

Jan 24 06:56:45 nginx-and-selinux systemd[1]: Starting The nginx HTTP and reverse proxy server...
Jan 24 06:56:45 nginx-and-selinux nginx[23989]: nginx: the configuration file /etc/nginx/nginx.conf... ok
Jan 24 06:56:45 nginx-and-selinux nginx[23989]: nginx: configuration file /etc/nginx/nginx.conf tes...ful
Jan 24 06:56:45 nginx-and-selinux systemd[1]: Failed to parse PID from file /run/nginx.pid: Invalid...ent
Jan 24 06:56:45 nginx-and-selinux systemd[1]: Started The nginx HTTP and reverse proxy server.
Hint: Some lines were ellipsized, use -l to show in full.


[root@nginx-and-selinux vagrant]# ss -tupnl | grep nginx
tcp    LISTEN     0      128       *:3080                  *:*                   users:(("nginx",pid=23995,fd=6),("nginx",pid=23994,fd=6))
tcp    LISTEN     0      128    [::]:80                 [::]:*                   users:(("nginx",pid=23995,fd=7),("nginx",pid=23994,fd=7))
```
Перед демонстрацией следующего метода останавливаем nginx и восстанавливаем исходный тип порта 3080:
```
[root@nginx-and-selinux vagrant]# systemctl stop nginx
[root@nginx-and-selinux vagrant]# semanage port -d -p tcp 3080
[root@nginx-and-selinux vagrant]# seinfo --portcon=3080
        portcon tcp 1024-32767 system_u:object_r:unreserved_port_t:s0
        portcon udp 1024-32767 system_u:object_r:unreserved_port_t:s0
        portcon sctp 1024-65535 system_u:object_r:unreserved_port_t:s0
```

## Использование переключателя
Переключатели (booleans) позволяют без перезапуска системы изменять части политик SELinux. Полезны, когда нужно решить проблему, но навыков по написанию политик нет.
Выполним предложенную утилитой sealert команду, включающую переключатель nis_enabled:
```
[root@nginx-and-selinux vagrant]# setsebool -P nis_enabled 1
```
Не могу толком сказать, что это за переключатель, однако nginx запустился, порт прослушивается (листинг соответствует предыдущему примеру).  
Судя по количеству баллов (7.83), присвоенных этому методу утилитой, данная настройка более глобальная, чем изменение типа порта (затрагивает много политик), поэтому рекомендуется к ограниченному использованию.  
Перед демонстрацией следующего метода останавливаем nginx и выключаем переключатель:
```
[root@nginx-and-selinux vagrant]# systemctl stop nginx
[root@nginx-and-selinux vagrant]# setsebool -P nis_enabled 0
```

## Формирование и установка модуля
Политики в SELinux реализованы в виде модулей - исполняемых файлов, подгружаемых в систему в процессе работы.  
Утилита sealert предлагает выполнить две команды, чтобы позволить nginx работать с нестандартным портом.
Первая команда выполняет поиск записей, относящихся к nginx, в логе SELinux, и генерирует на основании информации из лога модуль политики:
```
[root@nginx-and-selinux vagrant]# ausearch -c 'nginx' --raw | audit2allow -M my-nginx
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i my-nginx.pp
```
Текст модуля достаточно прост - он просто разрешает операцию `tcp_socket name_bind` для домена `httpd_t` по отношению к типу `unreserved_port_t`:
```
[root@nginx-and-selinux vagrant]# cat my-nginx.te

module my-nginx 1.0;

require {
        type httpd_t;
        type unreserved_port_t;
        class tcp_socket name_bind;
}

#============= httpd_t ==============

#!!!! This avc can be allowed using the boolean 'nis_enabled'
allow httpd_t unreserved_port_t:tcp_socket name_bind;
```
В тексте модуля есть и подсказка, что этого можно достигнуть и с помощью переключателя nis_enabled.
Вторая команда компилирует и устанавливает модуль:
```
[root@nginx-and-selinux vagrant]# semodule -i my-nginx.pp
```
После установки модуля политики nginx запустился нормально, порт 3080 прослушивается (листинг соответствует первому примеру).  
sealert практически не рекомендует этот метод к использованию (1.41 баллов) - слишком глобальное разрешение операции. Годится, чтобы нечто заработало здесь и сейчас, с последующим анализом ситуации и принятием более точечного решения.

