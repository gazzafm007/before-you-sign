<?php
// Stripe calls this when a Payment Link payment completes.
// Endpoint URL to give Stripe: https://<your site>/bys/stripe-webhook.php
// Events: checkout.session.completed, checkout.session.async_payment_succeeded

define('BYS', 1);
require __DIR__ . '/lib.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bys_json(405, ['error' => 'POST only']);
}

$cfg = bys_config();
$payload = (string) file_get_contents('php://input');
$sigHeader = $_SERVER['HTTP_STRIPE_SIGNATURE'] ?? '';

// --- Check Stripe's signature, so nobody else can mark a case as paid. ---
$t = null;
$sigs = [];
foreach (explode(',', $sigHeader) as $part) {
    $kv = explode('=', trim($part), 2);
    if (count($kv) !== 2) {
        continue;
    }
    if ($kv[0] === 't') {
        $t = $kv[1];
    } elseif ($kv[0] === 'v1') {
        $sigs[] = $kv[1];
    }
}
$secret = (string) $cfg['stripe_webhook_secret'];
if ($secret === '' || strpos($secret, 'REPLACE') !== false) {
    bys_log('webhook rejected: signing secret not set in config.php');
    bys_json(500, ['error' => 'Webhook secret not configured']);
}
if ($t === null || !ctype_digit($t) || !$sigs || abs(time() - (int) $t) > 300) {
    bys_log('webhook rejected: missing or stale signature');
    bys_json(400, ['error' => 'Bad signature']);
}
$expected = hash_hmac('sha256', $t . '.' . $payload, $secret);
$valid = false;
foreach ($sigs as $s) {
    if (hash_equals($expected, $s)) {
        $valid = true;
    }
}
if (!$valid) {
    bys_log('webhook rejected: signature does not match (wrong whsec_ secret?)');
    bys_json(400, ['error' => 'Bad signature']);
}

// --- Handle the event. ---
$event = json_decode($payload, true);
$type = $event['type'] ?? '';
$session = $event['data']['object'] ?? [];

if (!in_array($type, ['checkout.session.completed', 'checkout.session.async_payment_succeeded'], true)) {
    bys_json(200, ['ignored' => $type]); // Acknowledge so Stripe does not retry.
}

$ref = bys_ref($session['client_reference_id'] ?? '');
if ($ref === null) {
    bys_log('webhook: ' . $type . ' with no BYS reference, ignored (session ' . ($session['id'] ?? '?') . ')');
    bys_json(200, ['ignored' => 'no BYS reference']);
}

$livemode = !empty($event['livemode']);
if (!$livemode && empty($cfg['allow_test_payments'])) {
    bys_log("$ref test payment ignored (allow_test_payments is off)");
    bys_json(200, ['ignored' => 'test payment']);
}

$links = $cfg['payment_link_ids'] ?? [];
if ($links && !in_array($session['payment_link'] ?? '', $links, true)) {
    bys_log("$ref payment from an unlisted payment link ignored (" . ($session['payment_link'] ?? 'none') . ')');
    bys_json(200, ['ignored' => 'other payment link']);
}

if (($session['payment_status'] ?? '') !== 'paid') {
    // e.g. a bank transfer still clearing; async_payment_succeeded follows.
    bys_log("$ref checkout completed but payment_status is " . ($session['payment_status'] ?? '?'));
    bys_json(200, ['pending' => true]);
}

$file = bys_dir('payments') . '/' . $ref . '.json';
if (!is_file($file)) {
    $cd = $session['customer_details'] ?? [];
    bys_write_json($file, [
        'reference' => $ref,
        'paid_at' => date('c', (int) ($session['created'] ?? time())),
        'recorded_at' => date('c'),
        'session_id' => $session['id'] ?? '',
        'payment_intent' => $session['payment_intent'] ?? '',
        'payment_link' => $session['payment_link'] ?? '',
        'amount_total' => $session['amount_total'] ?? null,
        'currency' => $session['currency'] ?? '',
        'livemode' => $livemode,
        'name' => $cd['name'] ?? '',
        'email' => $cd['email'] ?? '',
        'phone' => $cd['phone'] ?? '',
        'event_id' => $event['id'] ?? '',
    ]);
    bys_log("$ref PAID " . ($livemode ? 'live' : 'TEST') . ' ' . ($session['amount_total'] ?? '?') . ' ' . ($session['currency'] ?? ''));
}

// If the documents arrived before the payment was confirmed, send them now.
bys_deliver_if_ready($ref);

bys_json(200, ['received' => true]);
