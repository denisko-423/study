#!/bin/sh

set -eux

whoami
uname -a
hostname -f
cd /root


yum install -y redhat-lsb-core rpmdevtools rpm-build createrepo yum-utils wget gcc

wget -q https://nginx.org/packages/centos/7/SRPMS/nginx-1.18.0-2.el7.ngx.src.rpm
rpm -i nginx-1.18.0-2.el7.ngx.src.rpm

wget -q https://www.openssl.org/source/latest.tar.gz
tar -xf latest.tar.gz

yum-builddep -y rpmbuild/SPECS/nginx.spec

cp rpmbuild/SPECS/nginx.spec oldnginx.spec
sed '/--with-debug/i \\t--with-openssl=/root/openssl-1.1.1h \\' oldnginx.spec > rpmbuild/SPECS/nginx.spec

rpmbuild -bb rpmbuild/SPECS/nginx.spec

yum localinstall -y rpmbuild/RPMS/x86_64/nginx-1.18.0-2.el7.ngx.x86_64.rpm
systemctl start nginx
systemctl status nginx

mkdir /usr/share/nginx/html/repo
cp rpmbuild/RPMS/x86_64/nginx-1.18.0-2.el7.ngx.x86_64.rpm /usr/share/nginx/html/repo/
wget -q --no-check-certificate -O /usr/share/nginx/html/repo/percona-release-1.0-9.noarch.rpm \
https://downloads.percona.com/downloads/percona-release/percona-release-1.0-9/redhat/percona-release-1.0-9.noarch.rpm

createrepo --workers=1 /usr/share/nginx/html/repo/

cp /etc/nginx/conf.d/default.conf olddefault.conf
sed '/index.html/a \\tautoindex on;' olddefault.conf > /etc/nginx/conf.d/default.conf

# Логично сначала всё подготовить, а затем запустить nginx.
# Однако на практике nginx валился с ошибкой.
# Пришлось сначала его стартовать, потом делать перезапуск.
# Объяснения такому поведению у меня нет.
nginx -t
nginx -s reload

