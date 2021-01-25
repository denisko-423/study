## Задание
Обеспечить работоспособность приложения при включенном selinux:
- развернуть приложенный стенд;
- выяснить причину неработоспособности механизма обновления зоны;
- предложить решение (или решения) для данной проблемы;
- выбрать одно из решений для реализации, предварительно обосновав выбор;
- реализовать выбранное решение и продемонстрировать его работоспособность.  

## Ситуация
После разворачивания стенда при попытке удаленно (с рабочей станции) внести изменения в зону ddns.lab обновления зоны не происходит, получаем ошибку со стороны сервера:  

```
$ vagrant ssh client
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
update failed: SERVFAIL
> quit
[vagrant@client ~]$ logout
Connection to 127.0.0.1 closed.
```

## Поиск причины ошибки
Сходу отметаем гипотезу о неправильной настройке сервера, иначе не стали бы привлекать экспертов)  
Статус сервиса DNS (`systemctl status named`) показывает, что сервис работает нормально.  
Но при просмотре лога (`journalctl -e`) обнаруживаем следующее:
```
...
named[4922]: /etc/named/dynamic/named.ddns.lab.view1.jnl: create: permission denied
...
setroubleshoot[4988]: SELinux is preventing isc-worker0000 from create access on the file named.ddns.lab.view1.jnl. For complete SELinux messages run: sealert -l 18787f32-bb02-45f7-9026-be949571c6e5
...
```
SELinux заблокировал попытку рабочего процесса isc-worker0000 (видимо, каким-то образом относящегося к сервису DNS) создать файл /etc/named/dynamic/named.ddns.lab.view1.jnl. При этом он оказался настолько любезен, что предложил и средство для детального изучения проблемы и поиска решения.  
Запускаем предложенную команду, и получаем развернутый ответ:
```
[root@ns01 vagrant]# sealert -l 18787f32-bb02-45f7-9026-be949571c6e5
SELinux is preventing isc-worker0000 from create access on the file named.ddns.lab.view1.jnl.

*****  Plugin catchall_labels (83.8 confidence) suggests   *******************

If you want to allow isc-worker0000 to have create access on the named.ddns.lab.view1.jnl file
Then you need to change the label on named.ddns.lab.view1.jnl
Do
# semanage fcontext -a -t FILE_TYPE 'named.ddns.lab.view1.jnl'
where FILE_TYPE is one of the following: dnssec_trigger_var_run_t, ipa_var_lib_t, krb5_host_rcache_t, krb5_keytab_t, named_cache_t, named_log_t, named_tmp_t, named_var_run_t, named_zone_t.
Then execute:
restorecon -v 'named.ddns.lab.view1.jnl'


*****  Plugin catchall (17.1 confidence) suggests   **************************

If you believe that isc-worker0000 should be allowed create access on the named.ddns.lab.view1.jnl file by default.
Then you should report this as a bug.
You can generate a local policy module to allow this access.
Do
allow this access for now by executing:
# ausearch -c 'isc-worker0000' --raw | audit2allow -M my-iscworker0000
# semodule -i my-iscworker0000.pp


Additional Information:
Source Context                system_u:system_r:named_t:s0
Target Context                system_u:object_r:etc_t:s0
Target Objects                named.ddns.lab.view1.jnl [ file ]
Source                        isc-worker0000
Source Path                   isc-worker0000
Port                          <Unknown>
Host                          ns01
Source RPM Packages           
Target RPM Packages           
Policy RPM                    selinux-policy-3.13.1-266.el7.noarch
Selinux Enabled               True
Policy Type                   targeted
Enforcing Mode                Enforcing
Host Name                     ns01
Platform                      Linux ns01 3.10.0-1127.el7.x86_64 #1 SMP Tue Mar
                              31 23:36:51 UTC 2020 x86_64 x86_64
Alert Count                   1
First Seen                    2021-01-23 12:52:44 UTC
Last Seen                     2021-01-23 12:52:44 UTC
Local ID                      18787f32-bb02-45f7-9026-be949571c6e5

Raw Audit Messages
type=AVC msg=audit(1611406364.365:1848): avc:  denied  { create } for  pid=4922 comm="isc-worker0000" name="named.ddns.lab.view1.jnl" scontext=system_u:system_r:named_t:s0 tcontext=system_u:object_r:etc_t:s0 tclass=file permissive=0


Hash: isc-worker0000,named_t,etc_t,file,create
```

Имеет место несоответствие контекстов, конкретно домена и типа: процесс работает с контекстом system\_u:system\_r:named\_t:s0 (домен named\_t), контекст каталога, где процесс пытается создать файл - system\_u:object\_r:etc\_t:s0 (тип etc\_t). Надо приводить контексты к общему знаменателю.

## Непринятое решение
Утилита sealert интересна тем, что предлагает несколько решений проблемы (если таковые существуют), при этом каждому решению присваивает баллы "уверенности". Чем больше баллов, тем более предпочтительным, с точки зрения утилиты, является решение.  
Второе предложенное утилитой решение с баллом 17.1 из 100 предлагает скомпилировать и установить в SELinux модуль политики. После выполнения предложенных команд получаем модуль со следующим текстом:
```
[root@ns01 vagrant]# ausearch -c 'isc-worker0000' --raw | audit2allow -M my-iscworker0000
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i my-iscworker0000.pp

[root@ns01 vagrant]# cat my-iscworker0000.te

module my-iscworker0000 1.0;

require {
        type etc_t;
        type named_t;
        class file create;
}

#============= named_t ==============

#!!!! WARNING: 'etc_t' is a base type.
allow named_t etc_t:file create;
```
Созданная политика разрешает любому процессу с доменом named\_t создавать файлы в каталогах с типом etc\_t. Так как этот тип по умолчанию имеют все файлы и подкаталоги в папке /etc, то фактически мы разрешаем процессу создавать файлы в любом месте каталога /etc с учетом прав файловой системы, что конечно снижает безопасность системы в целом. Решение рабочее, но грубое, типа "ковровой бомбардировки", поэтому оставим его на крайний случай.

## Первое решение для устранения проблемы
Первое предложенное утилитой решение с баллом 83.8 более привлекательно. Чтобы получить возможность создать нужный файл в указанном месте, предлагается выполнить две команды:
```
# semanage fcontext -a -t FILE_TYPE 'named.ddns.lab.view1.jnl'
# restorecon -v 'named.ddns.lab.view1.jnl'
```
Первая команда создает контекст по умолчанию для файла named.ddns.lab.view1.jnl. Вторая команда применяет созданный контекст к папке назначения (так как файла в ней пока не существует). Решение проблемы точечное (модификации подвергается только целевой каталог, а не вся папка /etc), с точки зрения безопасности системы более приемлемое, но требует доработки.  
Файл named.ddns.lab.view1.jnl в папке /etc/named/dynamic/ после выполнения команд можно создать. А как насчет создания других файлов в этой папке? Каждый раз выполнять команды? Вместо указания конкретного файла создадим дефолтный контекст для каталога со всем содержимым. На всякий случай поднимемся на уровень выше, чтобы охватить всю рабочую папку процесса (возможно, этого не стоило делать). Вместо имени файла укажем в командах шаблон:
```
# semanage fcontext -a -t FILE_TYPE "/etc/named(/.*)?"
# restorecon -R -v /etc/named
```
Теперо в каталоге /etc/named/ и во всех его подкаталогах можно создавать файлы. Осталось понять, какой тип (FILE_TYPE) нужно указать в создаваемом дефолтном контексте.  
Найдем среди политик SELinux те, которые позволяют домену named\_t создавать файлы:

```
[root@ns01 vagrant]# sesearch -s named_t -c file -Ad | grep create
   allow named_t named_cache_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t dnssec_trigger_var_run_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t krb5_host_rcache_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t named_var_run_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t ipa_var_lib_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t named_tmp_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t named_log_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t krb5_keytab_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ; 
   allow named_t named_zone_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ;
```
Наиболее привлекательной в списке выглядит следующая политика:
```
allow named_t named_cache_t : file { ioctl read write create getattr setattr lock append unlink link rename open } ;
```
Она разрешает домену named\_t выполнять все требуемые операции (создание, чтение, запись и т.д.) над объектом с типом named\_cache\_t. Выбор именно этого типа будет обоснован в дальнейшем.  
Подставляем выбранный тип и выполняем команды:
```
[root@ns01 vagrant]# semanage fcontext -a -t named_cache_t "/etc/named(/.*)?"

[root@ns01 vagrant]# restorecon -R -v /etc/named
restorecon reset /etc/named context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/named.dns.lab.view1 context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/named.dns.lab context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/dynamic context unconfined_u:object_r:etc_t:s0->unconfined_u:object_r:named_cache_t:s0
restorecon reset /etc/named/dynamic/named.ddns.lab context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/dynamic/named.ddns.lab.view1 context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/named.newdns.lab context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
restorecon reset /etc/named/named.50.168.192.rev context system_u:object_r:etc_t:s0->system_u:object_r:named_cache_t:s0
```
Теперь контекст каталога /etc/named/ и его содержимого выглядит так:
```
[root@ns01 vagrant]# ls -lRZ /etc/named
/etc/named:
drw-rwx---. root named unconfined_u:object_r:named_cache_t:s0 dynamic
-rw-rw----. root named system_u:object_r:named_cache_t:s0 named.50.168.192.rev
-rw-rw----. root named system_u:object_r:named_cache_t:s0 named.dns.lab
-rw-rw----. root named system_u:object_r:named_cache_t:s0 named.dns.lab.view1
-rw-rw----. root named system_u:object_r:named_cache_t:s0 named.newdns.lab

/etc/named/dynamic:
-rw-rw----. named named system_u:object_r:named_cache_t:s0 named.ddns.lab
-rw-rw----. named named system_u:object_r:named_cache_t:s0 named.ddns.lab.view1
```
И ожидаемо обновление зоны ddns.lab с рабочей станции выполняется успешно, файл на сервере создается:
```
$ vagrant ssh client
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
> quit
[vagrant@client ~]$ logout
Connection to 127.0.0.1 closed.

[root@ns01 vagrant]# ls -lZ /etc/named/dynamic
-rw-rw----. named named system_u:object_r:named_cache_t:s0 named.ddns.lab
-rw-rw----. named named system_u:object_r:named_cache_t:s0 named.ddns.lab.view1
-rw-r--r--. named named system_u:object_r:named_cache_t:s0 named.ddns.lab.view1.jnl
```
Данное решение пригодно для восстановления работы уже установленного, настроенного и работающего сервера, когда радикальное вмешательство неприемлемо.  
Исправленный по этому методу стенд находится в папке `dns\_problems\_solution_1`. Команды semanage и restorecon с парамтрами прописаны в playbook Ansible, остальные файлы стенда остались без изменений.

## Второе решение для устранения проблемы
Прав был человек, сказавший: _"Если все ваши попытки что-то сделать заканчиваются неудачно, внимательно прочитайте инструкцию"_. Обратимся к инструкции - справке по DNS-серверу (`man named`). Оказывается, в ней есть целый раздел "Red Hat SELinux BIND Security Profile", посвященный вопросам безопасности. Из текста раздела узнаем, что:
- разработчики всё продумали за нас,
- после установки пакета в SELinux появляется всё необходимое для нормальной работы DNS-сервера (типы, правила, дефолтные контексты),
- для разных каталогов и файлов определены соответствующие типы, а также права ФС,
- при установке пакета автоматически создаются три каталога (/var/named/slaves, /var/named/dynamic, /var/named/data), в которых сервису named разрешено создавать и изменять файлы,
- контекст по умолчанию в этих каталогах named\_cache\_t. Вот почему в первом решении был выбран этот тип, как рекомендованный самими разработчиками.  
Остается привести в соответствие с рекомендациями предложенный неработающий стенд.  
Исправленный по этому методу стенд находится в папке `dns\_problems\_solution\_2`. Изменения сделаны в конфиге DNS-сервера named.conf и плейбуке Ансибла - изменены пути расположения файлов, из плейбука исключены за ненадобностью секции назначения прав в каталогах. Для сравнения оставлены закомментированные строки со старыми путями.  
Это решение я считаю лучшим и рекомендуемым. Чем проще система, чем меньше в ней сущностей, тем более надежно и предсказуемо она работает.
