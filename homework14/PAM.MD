#### Задание: запретить всем пользователям, кроме группы admin, логин в выходные (суббота и воскресенье), без учета праздников.

Решить задачу можно с помощью модулей РАМ:  
- модулей, позволяющих задать расписание,
- модулей, выполняющих скрипт.

Из модулей, использующих расписание, для наших целей подходит только pam\_time. Модуль pam\_group по расписанию предоставляет членство (membership) аутентифицированного пользователя в заданных группах, что не соответствует поставленной задаче.  
Использование скрипта дает возможность реализовать практически любую логику управления пользователями. Выполнить скрипт позволяют два модуля - pam\_exec и pam\_script.  


## Использование модуля pam\_time
Работа модуля основана на последовательном применении к аутентифицированному пользователю правил из файла конфигурации. Помимо расписания, в правилах указываются как списки отдельных пользователей, так и сетевые группы пользователей (netgroup).  

Создаем файл конфигурации модуля в виде:
```
# cat /etc/security/time.conf
*;*;!@admin;!Wd
```
где  
* первое поле (\*) - сервисы РАМ, к которым применяется правило, в данном случае все,
* второе поле (\*) - терминалы, к которым применяется правило, в данном случае все,
* третье поле (!@admin) - пользователи или сетевая группа, к которым применяется правило, в данном случае указана сетевая группа @admin, знак ! означает отрицание,
* четвертое поле (!Wd) - расписание работы правила, Wd означает week-end (суббота и воскресенье), знак ! задает отрицание.  
В целом правило означает: пользователям, не входящим в группу admin, запрещен доступ ко всем сервисам со всех терминалов в выходные.  

Залогиниться в системе можно как локально с консоли, так и удаленно через ssh. Локальное подключение управляется сценарием /etc/pam.d/login, удаленное - /etc/pam.d/sshd. В этих сценариях нужно прописать модуль pam\_time.  
Тип модуля - только account (управление учетными записями), тип управления - required (после завершения модуля независимо от кода возврата выполнение сценария продолжается).  

Прописываем модуль в сценариях:
```
# cat /etc/pam.d/login
...
account    required     pam_nologin.so
account    required     pam_time.so
account    include      system-auth
...

# cat /etc/pam.d/sshd:
...
account    required     pam_nologin.so
account    required     pam_time.so
account    include      password-auth
...
```
Чтобы изменения вступили в силу, перезапускаем сервисы:
```
# systemctl restart systemd-logind.service
# systemctl restart sshd.service
```


## Использование модуля pam\_exec
Данный модуль выполняет только бинарные файлы, поэтому в качестве параметра модулю указывается командный интерпретатор, который и исполняет скрипт. Типы модуля и управления в сценариях оставляем без изменений.  

Вносим изменения в сценарии - заменяем pam\_time на pam\_exec с параметрами:
```
# cat /etc/pam.d/login
...
account    required     pam_nologin.so
account    required     pam_exec.so /bin/bash /opt/pamscript/admin.sh
account    include      system-auth
...

# cat /etc/pam.d/sshd:
...
account    required     pam_nologin.so
account    required     pam_exec.so /bin/bash /opt/pamscript/admin.sh
account    include      password-auth
...
```

Создаем скрипт:
```
# cat /opt/pamscript/admin.sh

#!/bin/bash

if [ `id -nG $PAM_USER | grep -w admin > /dev/null; echo $?` -eq 0 ]
  then exit 0
elif [ $(date +%a) == "Sat" ]
  then exit 9
elif [ $(date +%a) == "Sun" ]
  then exit 10
else exit 0
fi
```

Запуск скрипта с помощью командного интерпретатора указан в сценарии явно, давать права на исполнение файлу скрипта необязательно, достаточно прав на чтение всем:
```
# ls -l /opt/pamscript/admin.sh
-rw-r--r--. 1 root root 200 Jan 16 09:10 /opt/pamscript/admin.sh
```

Логика скрипта простая. Логин аутентифицированного пользователя скрипт получает через переменную окружения сценария $PAM_USER. Перечисляются группы, в которые входит пользователь (`id -nG`), и выполняется поиск нужной группы, без вариантов \*admin\* (`grep -w`). Если группа найдена, скрипт завершается успешно, т.е. возвращает код 0 - этот пользователь может беспрепятственно логиниться в систему. В противном случае проверяется день недели, и если это суббота или воскресенье - скрипт возвращает ненулевой код. Сценарий выполняется дальше (для модуля указан тип управления required), но если один из модулей сценария завершается с ненулевым кодом, то пользователю будет отказано в доступе к системе.  

Создаем двух пользователей, одного из них вместе с рутом добавляем в новую локальную группу admin:
```
# useradd user_admin && echo "blabla" | passwd --stdin user_admin
# useradd user_notadmin && echo "blabla" | passwd --stdin user_notadmin
# groupadd admin
# usermod -aG admin root
# usermod -aG admin user_admin
```

Чтобы изменения в сценариях вступили в силу, перезапускаем сервисы:
```
# systemctl restart systemd-logind.service
# systemctl restart sshd.service
```

Теперь можно проверить работу модуля. Пользователь user_notadmin, не входящий в группу admin, не может подключиться к серверу. По коду завершения 10 видно, что залогиниться он пытался в воскресенье:
```
denisko@denisko:~$ ssh -l root 192.168.10.10
root@192.168.10.10's password: 
[root@system-pam ~]# logout
Connection to 192.168.10.10 closed.

denisko@denisko:~$ ssh -l user_admin 192.168.10.10
user_admin@192.168.10.10's password: 
[user_admin@system-pam ~]$ logout
Connection to 192.168.10.10 closed.

denisko@denisko:~$ ssh -l user_notadmin 192.168.10.10
user_notadmin@192.168.10.10's password: 
/bin/bash failed: exit code 10
Connection closed by 192.168.10.10 port 22
```


## Использование модуля pam\_script
Модуль не входит в базовую конфигурацию, устанавливается из отдельного репозитория:
```
# for pkg in epel-release pam_script; do yum install -y $pkg; done
```
Модуль может использоваться на разных этапах выполнения сценария (auth, account, session, password), но для каждого этапа имя скрипта жестко задано. Так как мы будем использовать модуль аналогично предыдущим примерам (account), то переименуем скрипт согласно документации:
```
# mv /opt/pamscript/admin.sh /opt/pamscript/pam_script_acct
```
В отличие от pam\_exec, модуль pam\_script выполняет скрипт напрямую, поэтому файл скрипта должен быть исполняемым:
```
# chmod 0755 /opt/pamscript/pam_script_acct

# ls -l /opt/pamscript/pam_script_acct
-rwxr-xr-x. 1 root root 200 Jan 16 09:10 /opt/pamscript/pam_script_acct
```
По умолчанию модуль ищет скрипты в каталоге /etc. Для указания другого каталога есть соответствующий параметр, в данном случае укажем dir=/opt/pamscript/.  
Вносим изменения в сценарии - заменяем pam\_exec на pam\_script с параметром:
```
# cat /etc/pam.d/login
...
account    required     pam_nologin.so
account    required     pam_script.so dir=/opt/pamscript/
account    include      system-auth
...

# cat /etc/pam.d/sshd:
...
account    required     pam_nologin.so
account    required     pam_script.so dir=/opt/pamscript/
account    include      password-auth
...
```
Чтобы изменения вступили в силу, перезапускаем сервисы:
```
# systemctl restart systemd-logind.service
# systemctl restart sshd.service
```
Теперь можно проверить работу модуля. Пользователь user_notadmin, не входящий в группу admin, не может подключиться к серверу:
```
denisko@denisko:~$ ssh -l root 192.168.10.10
root@192.168.10.10's password: 
[root@system-pam ~]# logout
Connection to 192.168.10.10 closed.

denisko@denisko:~$ ssh -l user_admin 192.168.10.10
user_admin@192.168.10.10's password: 
[user_admin@system-pam ~]$ logout
Connection to 192.168.10.10 closed.

denisko@denisko:~$ ssh -l user_notadmin 192.168.10.10
user_notadmin@192.168.10.10's password: 
Connection closed by 192.168.10.10 port 22
```

