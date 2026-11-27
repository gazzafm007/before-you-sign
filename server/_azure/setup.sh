#!/bin/bash
# Clear to Sign server: create (or update) the Azure web app and deploy the
# server from GitHub. Run in Azure Cloud Shell (Bash):
#   curl -sL https://raw.githubusercontent.com/gazzafm007/before-you-sign/checker-v0.2/server/_azure/setup.sh | bash
# Safe to run again: it only creates what is missing, then redeploys.
set -euo pipefail
RG=arpra-apps; PLAN=arpra-apps-plan; LOC=australiaeast; BRANCH=${BRANCH:-checker-v0.2}
APP=${APP:-arpra-apps}
say(){ echo; echo "=== $*"; }

say "1/6 Resource group and plan"
az account set --subscription "$(az account list --query "[?state=='Enabled']|[0].id" -o tsv)"
az group create -n $RG -l $LOC -o none
az appservice plan show -g $RG -n $PLAN -o none 2>/dev/null || \
  az appservice plan create -g $RG -n $PLAN -l $LOC --is-linux --sku B1 -o none

say "2/6 Web app"
if ! az webapp show -g $RG -n $APP -o none 2>/dev/null; then
  RT="PHP:8.4"
  az webapp list-runtimes --os linux -o tsv 2>/dev/null | grep -q '8.4' || RT="PHP:8.3"
  az webapp create -g $RG -p $PLAN -n $APP --runtime "$RT" -o none || {
    APP=arpra-apps-$RANDOM; echo "Name taken, using $APP"
    az webapp create -g $RG -p $PLAN -n $APP --runtime "$RT" -o none; }
fi
echo "$APP" > ~/cts-app-name.txt

say "3/6 Settings"
az webapp config set -g $RG -n $APP --always-on true --ftps-state Disabled \
  --startup-file "bash /home/site/wwwroot/_azure/startup.sh" -o none
az webapp update -g $RG -n $APP --https-only true -o none
az webapp config appsettings set -g $RG -n $APP -o none --settings \
  "PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d:/home/site/wwwroot/_azure/ini" \
  "BYS_CONFIG=/home/site/private/config.php" \
  "WEBSITE_SKIP_RUNNING_KUDUAGENT=false" "TZ=Australia/Sydney" \
  "SCM_DO_BUILD_DURING_DEPLOYMENT=false"

say "4/6 Fetch the server from GitHub ($BRANCH)"
W=$(mktemp -d); cd "$W"
curl -sL "https://codeload.github.com/gazzafm007/before-you-sign/zip/refs/heads/$BRANCH" -o src.zip
unzip -q src.zip; SRC=$(ls -d before-you-sign-*/server)
mkdir -p pkg/App_Data/jobs/triggered/cts-retry
cp -r "$SRC/bys" pkg/bys; rm -f pkg/bys/config.php
cp -r "$SRC/_azure" pkg/_azure
cp "$SRC/_azure/webjob/run.sh" pkg/App_Data/jobs/triggered/cts-retry/run.sh
printf '{ "schedule": "0 */15 * * * *", "is_singleton": true }\n' > pkg/App_Data/jobs/triggered/cts-retry/settings.job
printf '<!doctype html><title>ARPRA apps</title><p>ARPRA Limited.</p>\n' > pkg/index.html
(cd pkg && zip -qr ../site.zip .)

say "5/6 Deploy"
az webapp deploy -g $RG -n $APP --src-path site.zip --type zip --restart true -o none

HOST=$(az webapp show -g $RG -n $APP --query defaultHostName -o tsv)
echo "$HOST" > ~/cts-host.txt
say "6/6 Checks (the app can take a minute to start)"
sleep 30
for p in bys/web-config.php bys/config.php bys/prompt/system.txt; do
  printf '%-28s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' https://$HOST/$p)"
done
echo
echo "Web app: $APP   Address: https://$HOST"
echo "Expected: web-config.php 500 until the settings file is installed, the other two 403."
