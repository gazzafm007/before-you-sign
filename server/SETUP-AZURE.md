## Azure server set-up

The Clear to Sign server moves to an Azure web app at **apps.arpra.org.au**. The app, the website and Stripe only ever use that address. Allow about two hours. Work through the steps in order once the nonprofit credits show in Azure.

### 1. Check the credits and set a spending alert

1. In the Azure portal, open **Cost Management + Billing → Azure credits** and confirm the US$2,000 sponsorship shows. Note the subscription's name (usually *Azure Sponsorship*).
2. **Cost Management → Budgets → Add**: US$100 a month on that subscription, emailing gary.martin@arpra.org.au at 80%. The server should cost well under this.

### 2. Create the web app

1. **Resource groups → Create**: name `arpra-apps`, region **Australia East**.
2. **App Services → Create → Web App**:
    - Subscription: the sponsorship. Resource group: `arpra-apps`.
    - Name: `arpra-apps`. Publish: **Code**. Runtime stack: **PHP 8.4**. Operating system: **Linux**. Region: **Australia East**.
    - Pricing plan: create `arpra-apps-plan`, **Basic B1**. (Free and Shared plans can't use a custom domain with SSL or "Always on".)
    - Review + create. Note the **Default domain** on the Overview page (for example `arpra-apps-xxxx.australiaeast-01.azurewebsites.net`).

### 3. Settings

In the web app, open **Settings → Configuration** (General settings):

- Startup Command: `bash /home/site/wwwroot/_azure/startup.sh`
- Always on: **On** (needed for the scheduled job)
- SCM Basic Auth Publishing Credentials: **On** (needed for GitHub to deploy)
- FTP state: **Disabled**. HTTPS Only: **On**.

Then **Settings → Environment variables → App settings**, add:

| Name | Value |
| --- | --- |
| PHP_INI_SCAN_DIR | /usr/local/etc/php/conf.d:/home/site/wwwroot/_azure/ini |
| BYS_CONFIG | /home/site/private/config.php |
| WEBSITE_SKIP_RUNNING_KUDUAGENT | false |
| TZ | Australia/Sydney |

Apply, then **Restart** the app.

### 4. Connect GitHub so the server deploys itself

1. Web app **Overview → Download publish profile**.
2. GitHub, repository gazzafm007/before-you-sign → **Settings → Secrets and variables → Actions**:
    - Secrets tab → New repository secret: `AZURE_WEBAPP_PUBLISH_PROFILE` = the whole contents of the downloaded file.
    - Variables tab → New repository variable: `AZURE_WEBAPP_NAME` = `arpra-apps`.
3. **Actions → Deploy server to Azure → Run workflow** (branch `checker-v0.2`). Wait for the green tick. From now on, any change to the server files in GitHub deploys by itself.

### 5. Put the settings file in place

1. Make a **new `app_key`**: 40 random letters and numbers, no symbols. It goes in config.php and in Codemagic, and must not change after the apps are released.
2. In your current config.php change three things:
    - `'app_key' => '<the new key>',`
    - `'data_dir' => '/home/site/bys-data',`
    - `'web_payment_link'` stays as it is for now.
3. Web app → **Development Tools → SSH → Go**. Type these two lines:
    - `mkdir -p /home/site/private /home/site/bys-data`
    - `cat > /home/site/private/config.php`
4. Paste the whole of config.php, press **Enter**, then **Ctrl+D**. Type `php -l /home/site/private/config.php`; it must say *No syntax errors*.
5. **Restart** the web app.

Check it, using the default domain from step 2:

- `https://<default domain>/bys/web-config.php` shows a line of settings starting `{"enabled"`.
- `https://<default domain>/bys/config.php` and `/bys/prompt/system.txt` show **403 Forbidden**.

### 6. The scheduled job (replaces the cPanel cron job)

Web app → **Settings → WebJobs → Add**:

- Name `cts-retry`. File: `clear-to-sign-webjob.zip` (in the repository's `server/_azure` folder).
- Type **Triggered**. Triggers **Scheduled**. CRON expression `0 */15 * * * *` (every 15 minutes).

Select it and choose **Run** once. Its log should finish without errors.

### 7. The address apps.arpra.org.au

1. Web app → **Settings → Custom domains → Add custom domain**: Domain provider **All other domain services**; TLS/SSL certificate **App Service Managed Certificate**; Domain `apps.arpra.org.au`.
2. Azure shows two DNS records. In **GoDaddy → arpra.org.au → DNS**, add:
    - **CNAME**, name `apps`, value = the default domain.
    - **TXT**, name `asuid.apps`, value = the verification ID Azure shows.
3. Back in Azure select **Validate**, then **Add**. The certificate can take up to 30 minutes.
4. Check `https://apps.arpra.org.au/bys/web-config.php` opens with a padlock.

### 8. Point Stripe and the website at the new address

- **Stripe → Developers → Webhooks**: change the endpoint URL to `https://apps.arpra.org.au/bys/stripe-webhook.php`. The signing secret stays the same.
- **Stripe → Payment Links → your link → After payment**: redirect to `https://apps.arpra.org.au/bys/thanks.html`.
- **Website** (v2 folder): in `assets/bys-online.js` change the line near the top to `var BYS_SERVER = "https://apps.arpra.org.au/bys";`
- Leave the old `/bys` folder on GoDaddy in place until the store apps are live, then delete it and its cron job.

### 9. Test

- On the website's online check, run a check with a sample document and pay with the Stripe test card. The request should arrive in the prepurchase@ mailbox.
- The log is at `/home/site/bys-data/bys.log` (open it with `tail -50 /home/site/bys-data/bys.log` in SSH).
