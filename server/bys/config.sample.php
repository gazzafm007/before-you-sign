<?php
// Before You Sign — server settings.
// Copy this file to config.php in the same folder and fill it in.
// config.php is never sent to browsers (see .htaccess) and must never be
// committed to GitHub.

return [
    // Stripe webhook signing secret: Stripe Dashboard → Developers → Webhooks
    // → your endpoint → "Signing secret" (starts with whsec_). The sandbox
    // and live endpoints each have their own secret.
    'stripe_webhook_secret' => 'whsec_REPLACE_ME',

    // Accept payments made in the Stripe sandbox (test cards)?
    // true while testing. Set to false when you go live, so a test payment can
    // never unlock a real review.
    'allow_test_payments' => true,

    // Optional: only accept payments from these Payment Link IDs (plink_...).
    // Find the ID in Stripe → Payment Links → your link. Leave empty to accept
    // any Checkout payment that carries a BYS- reference.
    'payment_link_ids' => [],

    // Shared key the app sends with every request (Settings → "Server key" in
    // the app). Make one up: 30+ random letters and numbers.
    'app_key' => 'REPLACE_WITH_A_LONG_RANDOM_KEY',

    // Where review requests are emailed.
    'mail_to' => 'prepurchase@arpra.org.au',

    // How to send that email:
    //  'graph' = through ARPRA's Microsoft 365 (recommended — the same kind of
    //            Entra app registration the mediation app uses). Fill in the
    //            'graph' block below.
    //  'php'   = through this hosting server's own mail. Simpler, but large
    //            attachments are left on the server and the email may land
    //            in junk unless SPF is set up (see SETUP.md).
    'mail_method' => 'graph',

    'graph' => [
        'tenant_id' => 'REPLACE_ME',      // Entra → Overview → Directory (tenant) ID
        'client_id' => 'REPLACE_ME',      // Entra → App registrations → your app → Application (client) ID
        'client_secret' => 'REPLACE_ME',  // the app's client secret VALUE
        'sender' => 'prepurchase@arpra.org.au', // mailbox the email is sent from
    ],

    // For 'php' only: the From address, and the size (MB) above which the
    // documents are left on the server instead of attached.
    'mail_from' => 'beforeyousign@arpra.org.au',
    'max_email_mb' => 20,

    // Largest upload accepted from the app, in MB. Must not be more than the
    // PHP upload limits in .user.ini.
    'max_upload_mb' => 60,

    // Days to keep the uploaded documents on the server after they have been
    // emailed to ARPRA (deleted by retry.php's cron job). 0 = keep forever.
    'keep_days' => 90,

    // Folder for payment records and uploaded documents. Keep it OUTSIDE
    // public_html so nothing in it can be opened from the web.
    // Default: a "bys-data" folder next to public_html.
    'data_dir' => dirname(__DIR__, 2) . '/bys-data',
];
