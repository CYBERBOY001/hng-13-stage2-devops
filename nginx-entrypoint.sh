#!/bin/sh
set -e

export PRIMARY="app_blue:8080"
export BACKUP="app_green:8080"

# Substitute only our custom vars, not Nginx internal ones
envsubst '$PRIMARY $BACKUP' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
