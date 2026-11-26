#!/bin/bash
# Clear to Sign server - Azure App Service (Linux, PHP 8.x) start-up.
# Set as the Startup Command: bash /home/site/wwwroot/_azure/startup.sh
# Adds to the built-in NGINX site: a 64 MB upload limit, and blocks the
# settings, helper files, checking instructions and this folder from the web
# (NGINX ignores the .htaccess files used on cPanel).
CONF=/etc/nginx/sites-enabled/default
[ -f "$CONF" ] || CONF=/etc/nginx/sites-available/default
if ! grep -q "clear-to-sign" "$CONF"; then
  sed -i '0,/server_name[^;]*;/s//&\
    # clear-to-sign\
    client_max_body_size 64M;\
    fastcgi_read_timeout 900;\
    location ^~ \/_azure\/ { deny all; }\
    location ^~ \/bys\/prompt\/ { deny all; }\
    location ~* ^\/bys\/(config.*\\.php|lib\\.php|check_lib\\.php|retry\\.php|.*\\.md|\\.user\\.ini|\\.htaccess)$ { deny all; }/' "$CONF"
fi
service nginx reload
