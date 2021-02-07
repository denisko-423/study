FROM alpine:3.13
RUN  apk update \
&&   apk upgrade --no-cache \
&&   addgroup -g 101 -S nginx \
&&   adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
&&   apk add --allow-untrusted --no-cache -X "https://nginx.org/packages/mainline/alpine/v3.13/main" "nginx=1.19.6-r1"
COPY ./nginx.* /etc/nginx/
EXPOSE 8888
ENTRYPOINT ["nginx", "-g", "daemon off;"]

