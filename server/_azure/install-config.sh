#!/bin/bash
# Installs config.php on the Azure web app, outside the web folder.
# 1. In Cloud Shell, Manage files > Upload, choose your config.php.
# 2. Run:
#   curl -sL https://raw.githubusercontent.com/gazzafm007/before-you-sign/checker-v0.2/server/_azure/install-config.sh | bash
# It gives the app a new random app_key (saved to ~/cts-app-key.txt, never
# shown on screen) and points the data folder at /home/site/bys-data.
set -euo pipefail
RG=arpra-apps; APP=$(cat ~/cts-app-name.txt); HOST=$(cat ~/cts-host.txt)
[ -f ~/config.php ] || { echo "Upload config.php to Cloud Shell first (Manage files > Upload)."; exit 1; }
cp ~/config.php ~/config.azure.php
if [ ! -s ~/cts-app-key.txt ]; then
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40 > ~/cts-app-key.txt
fi
KEY=$(cat ~/cts-app-key.txt)
sed -i -E "s#'app_key'[[:space:]]*=>[[:space:]]*'[^']*'#'app_key' => '${KEY}'#" ~/config.azure.php
if grep -q "'data_dir'" ~/config.azure.php; then
  sed -i -E "s#'data_dir'[[:space:]]*=>.*#'data_dir' => '/home/site/bys-data',#" ~/config.azure.php
fi
grep -q "$KEY" ~/config.azure.php || { echo "Could not set app_key - check config.php"; exit 1; }
php -l ~/config.azure.php >/dev/null 2>&1 || echo "(php not available here to check syntax; the server will check it)"
SCM=$(az webapp show -g $RG -n $APP --query "enabledHostNames[?contains(@,'.scm.')]|[0]" -o tsv)
TOKEN=$(az account get-access-token --query accessToken -o tsv)
for d in site/private/ site/bys-data/; do
  curl -s -o /dev/null -w "create $d %{http_code}\n" -X PUT -H "Authorization: Bearer $TOKEN" "https://$SCM/api/vfs/$d"
done
curl -s -o /dev/null -w "upload config %{http_code}\n" -X PUT -H "Authorization: Bearer $TOKEN" -H "If-Match: *" \
  --data-binary @"$HOME/config.azure.php" "https://$SCM/api/vfs/site/private/config.php"
rm -f ~/config.azure.php
az webapp restart -g $RG -n $APP -o none
sleep 30
echo "web-config.php: $(curl -s https://$HOST/bys/web-config.php | head -c 120)"
echo
echo "Done. The new app key is saved in ~/cts-app-key.txt (for Codemagic: run  cat ~/cts-app-key.txt  yourself)."
