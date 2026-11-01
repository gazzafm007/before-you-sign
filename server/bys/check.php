<?php
// The app asks: has Stripe confirmed payment for this case?
// GET check.php?ref=BYS-1A2B3C4D   (header X-BYS-Key: <app_key>)
// Reply: {"ref":"BYS-…","paid":true|false,"test":bool,"received":bool,"emailed":bool}

define('BYS', 1);
require __DIR__ . '/lib.php';

bys_require_app_key();
$ref = bys_ref($_GET['ref'] ?? '');
if ($ref === null) {
    bys_json(400, ['error' => 'Bad reference']);
}

$pay = bys_payment($ref);
$dir = bys_request_dir($ref);

// Paid and uploaded but the email failed earlier: try again, at most once a
// minute, while the buyer's app is checking.
if ($pay !== null && is_file($dir . '/request.json') && !is_file($dir . '/emailed.json')) {
    $mark = $dir . '/.last_attempt';
    if (!is_file($mark) || time() - filemtime($mark) > 60) {
        touch($mark);
        bys_deliver_if_ready($ref);
    }
}
bys_json(200, [
    'ref' => $ref,
    'paid' => $pay !== null,
    'test' => $pay !== null && empty($pay['livemode']),
    'received' => is_file($dir . '/request.json'),
    'emailed' => is_file($dir . '/emailed.json'),
]);
