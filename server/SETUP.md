# Before You Sign — server set-up (ARPRA cPanel hosting + Stripe)

These scripts let the app confirm a payment with Stripe instead of trusting the
buyer, and receive the buyer's documents. ARPRA gets one email at
**prepurchase@arpra.org.au** only when a request is both **uploaded** and
**paid**.

```
Buyer's phone ──pays──▶ Stripe ──webhook──▶ /bys/stripe-webhook.php ─┐
      │                                                              ├─▶ email to prepurchase@
      ├──"is BYS-… paid?"──▶ /bys/check.php                          │
      └──documents────────▶ /bys/request.php ────────────────────────┘
```

| File | What it does |
| --- | --- |
| `stripe-webhook.php` | Stripe calls it when a payment completes. Checks Stripe's signature and records the case reference (BYS-…) as paid. |
| `check.php` | The app asks whether a reference is paid. |
| `request.php` | The app uploads the report, documents and case file. |
| `thanks.html` | Page the buyer sees after paying ("go back to the app"). |
| `retry.php` | Cron job: re-sends any email that failed, and deletes old uploads. |
| `lib.php`, `config.php` | Shared code and your settings. Blocked from the web. |

Payment records and documents are stored in **`bys-data`**, a folder next to
`public_html` (not inside it), so nothing in it can be opened from the web.

Allow about an hour. Do the steps in order. Everything here uses the Stripe
**sandbox**; going live is at the end.

---

## 1. Upload the scripts

1. Log in to ARPRA's GoDaddy cPanel and open **File Manager**.
2. Click **Settings** (top right), tick **Show Hidden Files (dotfiles)**, Save.
   The folder includes two hidden files, `.htaccess` and `.user.ini`.
3. Open `public_html` and create a folder called **`bys`**.
4. Upload everything from the repository's `server/bys/` folder into it:
   `.htaccess`, `.user.ini`, `check.php`, `config.sample.php`, `index.html`,
   `lib.php`, `request.php`, `retry.php`, `stripe-webhook.php`, `thanks.html`.

## 1b. Let the scripts through the website firewall

ARPRA's site sits behind **GoDaddy Website Security** (Sucuri). It blocks
automated POST requests as "Fake bot access", which stops Stripe's webhook
(and can stop the app). The scripts check their own callers — Stripe's
signature and the app key — so the `/bys/` folder can safely bypass it:

1. Open GoDaddy **Website Security** for arpra.org.au → **Firewall** →
   **Settings** (or the Sucuri dashboard) → **Access Control**.
2. Under **Allowlist URL Paths** (may be called "Whitelist URL Paths"), add
   `/bys/` with the pattern set to **begins with**. Save.
3. If there is no such option, open a GoDaddy support ticket asking them to
   allowlist the path `/bys/` on www.arpra.org.au for Stripe webhooks and the
   app (block reason seen: FBP007 "Fake bot access").

Changes can take a few minutes to apply.

## 2. Check PHP

1. cPanel → **MultiPHP Manager**: the domain should be on **PHP 8.1 or later**.
2. cPanel → **Select PHP Version → Extensions** (if shown): make sure
   **curl** and **mbstring** are ticked.
3. The upload limits are set by `.user.ini` (64 MB). If your hosting ignores
   it, set the same values in cPanel → **MultiPHP INI Editor** for the domain:
   `upload_max_filesize 64M`, `post_max_size 70M`, `max_file_uploads 40`.

## 3. Create config.php

1. In `public_html/bys`, copy `config.sample.php` to **`config.php`**
   (right-click → Copy), then **Edit** `config.php`.
2. **`app_key`**: make up a long random key, at least 30 letters and numbers
   (a password manager's generator is ideal). You will type the same key into
   the app.
3. **`mail_to`**: leave as `prepurchase@arpra.org.au`.
4. Leave `stripe_webhook_secret` for now (step 6) and set up email in step 4.
5. Save.

**Check it works:** in a browser open
`https://www.arpra.org.au/bys/check.php?ref=BYS-00000000`.
You should see `{"error":"Not allowed."}` — that means the script runs and is
refusing requests without the key. Then open
`https://www.arpra.org.au/bys/config.php` — you should get **Forbidden**.
If you see the file's contents or a download, stop and tell Claude.

## 4. Email: Microsoft 365 (recommended)

The scripts send the request email through ARPRA's Microsoft 365, from the
prepurchase@ mailbox, the same way the mediation app sends email. This avoids
junk-mail problems and handles attachments up to 140 MB.

### 4a. App registration (Microsoft Entra admin centre)

Use a **separate** app registration for Before You Sign, so its secret can be
replaced without affecting the mediation app.

1. Go to <https://entra.microsoft.com> as a Microsoft 365 admin.
2. **App registrations → New registration**. Name: `Before You Sign server`.
   Supported account types: the **single-tenant** option, the one that names
   ARPRA's own directory (worded "Accounts in this organizational directory
   only (ARPRA only – Single tenant)" or "Single tenant only", depending on the
   version of the page). Not the options mentioning multiple tenants or
   personal Microsoft accounts. No redirect URI. **Register**.
3. On the app's **Overview** page copy the **Application (client) ID** and the
   **Directory (tenant) ID**.
4. **Certificates & secrets → New client secret**. Description
   `bys server`, expiry 24 months. Copy the **Value** straight away (it is only
   shown once). Put a reminder in the calendar to renew it before it expires.
5. **API permissions → Add a permission → Microsoft Graph → Application
   permissions → Mail.Send → Add**. Then click **Grant admin consent for
   ARPRA**. The status must show a green tick.

> Mail.Send as an application permission lets this app send as any mailbox in
> ARPRA. To limit it to prepurchase@ only, Microsoft's "RBAC for Applications"
> in Exchange Online can scope it to one mailbox (an Exchange PowerShell task;
> Claude can give you the exact commands). Recommended before going live.

### 4b. Put the details in config.php

```php
'mail_method' => 'graph',
'graph' => [
    'tenant_id' => '<Directory (tenant) ID>',
    'client_id' => '<Application (client) ID>',
    'client_secret' => '<client secret Value>',
    'sender' => 'prepurchase@arpra.org.au',
],
```

The email arrives in prepurchase@ **from** prepurchase@, with a copy in its
Sent Items. Replying goes to the buyer (it is set as the Reply-To).

### Alternative: the hosting server's own mail

Set `'mail_method' => 'php'` instead. Simpler, but:

- cPanel → **Email Routing** → choose arpra.org.au → set
  **Remote Mail Exchanger**. Without this, cPanel tries to deliver
  @arpra.org.au mail on the web server instead of sending it to Microsoft 365,
  and nothing arrives.
- cPanel → **Email Deliverability** shows whether arpra.org.au's SPF record
  allows the server to send. If not, emails will land in junk or be rejected.
  The SPF record lives in ARPRA's DNS (GoDaddy); it must keep Microsoft's
  `include:spf.protection.outlook.com` as well.
- Emails over `max_email_mb` (20 MB) are sent without attachments; the files
  stay in `bys-data/requests/BYS-…/files/` (File Manager).

## 5. Cron job (retries and clean-up)

cPanel → **Cron Jobs** → add:

- Common settings: **Twice per hour** (or `*/15 * * * *`).
- Command (replace `CPANELUSER` with ARPRA's cPanel username, shown on the
  right of the cPanel home page):

```
php /home/CPANELUSER/public_html/bys/retry.php
```

If cPanel reports `php: command not found`, use `/usr/local/bin/php` instead.

This re-sends any paid request whose email failed (for example, if Microsoft
365 was down), and deletes stored documents 90 days after they were emailed
(`keep_days` in config.php).

## 6. Stripe (sandbox)

### 6a. Webhook

1. In the Stripe Dashboard, make sure you are in the **sandbox** (the
   account picker, top left; there is a test-data banner).
2. Go to **Developers → Webhooks** (in newer dashboards: **Workbench →
   Webhooks**) and click **Add destination** (or **Add endpoint**).
3. Events from **Your account**. Select these two events:
   - `checkout.session.completed`
   - `checkout.session.async_payment_succeeded`
4. Destination type: **Webhook endpoint**. Endpoint URL:
   `https://www.arpra.org.au/bys/stripe-webhook.php`
   Description: `Before You Sign`. Create it.
5. On the new endpoint's page, reveal the **Signing secret** (`whsec_…`) and
   paste it into `config.php` as `stripe_webhook_secret`. Save.

### 6b. Payment Link

1. **Payment Links** → open your test link → **Edit** (or create a new one).
2. Product: e.g. "ARPRA pre-purchase review (incl. 12 months' membership)".
   Use a placeholder price until the fee is decided.
3. Options: tick **Collect customers' phone numbers** (and names if offered).
4. **After payment** tab: choose **Don't show confirmation page** →
   **Redirect customers to your website**:
   `https://www.arpra.org.au/bys/thanks.html`
5. Save. Optional: copy the link's ID (`plink_…`) into `payment_link_ids` in
   config.php so only this link can mark a case paid.

## 7. The app

In Before You Sign → **Settings**:

- **Stripe Payment Link**: the sandbox link (`https://buy.stripe.com/test_…`)
- **ARPRA server**: `https://www.arpra.org.au/bys`
- **Server key**: the `app_key` from config.php
- Save.

If the ARPRA server is left blank, the app falls back to the old test-build
flow (asks the buyer, emails from the phone).

## 8. Test it end to end

1. Run a check on a sample document, open **Get ARPRA to review**, fill in
   your details and tap **Pay with card**.
2. Pay with **4242 4242 4242 4242**, any future expiry, any CVC.
3. You land on the thank-you page. Go back to the app: within a few seconds the
   button changes to **Paid (test payment)**.
4. Tap **Send my documents**. You should see **Sent to ARPRA**, and an email
   "Pre-purchase review request BYS-…" arrives in prepurchase@ marked
   **TEST / SANDBOX PAYMENT**, with the report, documents and case file attached.

**If something does not work**

- Stripe → the webhook endpoint → **Event deliveries** shows each attempt
  and the script's reply. A `400 Bad signature` means the `whsec_` secret in
  config.php does not match this endpoint. You can **Resend** an event.
- `bys-data/bys.log` (File Manager, next to `public_html`) records every
  payment, upload and email, including Microsoft 365 error messages.
- In the app, a "server key was not accepted" message means the key in
  Settings does not match `app_key`.

## 9. Going live (later)

1. Decide the fee and GST, and set the **Fee shown to buyers** text in the app.
2. In Stripe **live mode**: create the live Payment Link (same settings) and a
   live webhook endpoint (same URL and events). It has its **own** `whsec_`
   signing secret — put that in config.php in place of the sandbox one.
3. In config.php set `'allow_test_payments' => false` so a test payment can
   never unlock a review, and update `payment_link_ids` to the live link.
4. Put the live Payment Link into the app's Settings (later, the public app
   will have it built in).
5. Scope the Entra app to the prepurchase@ mailbox (see 4a).

## Privacy notes

- Buyers' documents are personal information. They are stored only in
  `bys-data`, outside the web folder, and deleted after `keep_days`.
- `config.php` holds secrets. Never email it or commit it to GitHub
  (`.gitignore` already excludes it).
- Anyone with File Manager access to the hosting can read `bys-data`. Keep the
  cPanel login limited to those who need it.
