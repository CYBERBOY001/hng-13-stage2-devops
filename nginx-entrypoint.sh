#!/bin/sh

# Substitute only our custom vars, not Nginx internal ones
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
