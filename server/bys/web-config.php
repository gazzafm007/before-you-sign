<?php
// Settings the website's Before You Sign page needs (nothing secret).
// GET web-config.php -> {"enabled":bool,"turnstile_sitekey":…,"payment_link":…,"fee_text":…}

define('BYS', 1);
require __DIR__ . '/lib.php';

bys_web_headers();
$cfg = bys_config();
bys_json(200, [
    'enabled' => !empty($cfg['web_enabled']),
    'turnstile_sitekey' => (string) ($cfg['turnstile_sitekey'] ?? ''),
    'payment_link' => (string) ($cfg['web_payment_link'] ?? ''),
    'fee_text' => (string) ($cfg['web_fee_text'] ?? ''),
    'reply_promise' => (string) ($cfg['reply_promise'] ?? 'within 3 business days'),
]);
