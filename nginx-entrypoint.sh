#!/bin/sh
set -e

export PRIMARY="app_blue:8080"
export BACKUP="app_green:8080"

envsubst '${PRIMARY} ${BACKUP}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf


exec nginx -g 'daemon off;'
