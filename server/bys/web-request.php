<?php
// The website asks ARPRA to review a check it has already run. The documents
// are already on the server (from analyse.php), so only the buyer's details
// are sent. They are emailed to ARPRA once Stripe has confirmed payment.
//
// POST form (header X-BYS-Device: web-…): ref, meta (JSON: contact, title)
// Reply: {"ok":true,"paid":bool,"emailed":bool}

define('BYS', 1);
require __DIR__ . '/lib.php';
require __DIR__ . '/check_lib.php';

bys_web_headers();
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bys_json(405, ['error' => 'POST only']);
}
$ref = bys_ref($_POST['ref'] ?? '');
$device = preg_replace('/[^A-Za-z0-9-]/', '', (string) ($_SERVER['HTTP_X_BYS_DEVICE'] ?? ''));
$job = $ref === null ? null : bys_job($ref);
if ($ref === null || !bys_is_web_device($device) || $job === null || !hash_equals((string) ($job['device'] ?? ''), $device)) {
    bys_json(403, ['error' => 'Not allowed.']);
}
$meta = json_decode((string) ($_POST['meta'] ?? ''), true);
$c = is_array($meta['contact'] ?? null) ? $meta['contact'] : [];
if (!filter_var(trim((string) ($c['email'] ?? '')), FILTER_VALIDATE_EMAIL) || trim((string) ($c['name'] ?? '')) === '') {
    bys_json(400, ['error' => 'Please enter your name and a valid email address.']);
}

$dir = bys_request_dir($ref);
if (is_file($dir . '/emailed.json')) {
    bys_json(200, ['ok' => true, 'paid' => true, 'emailed' => true]);
}
$src = bys_check_dir($ref) . '/files';
$files = glob($src . '/*') ?: [];
if (!$files) {
    bys_json(410, ['error' => 'Your documents are no longer on our server (they are deleted after a few days). Please run the check again, then ask for the review.']);
}
if (!is_dir($dir . '/files') && !mkdir($dir . '/files', 0700, true) && !is_dir($dir . '/files')) {
    bys_json(500, ['error' => 'Cannot store your request.']);
}
$names = [];
foreach ($files as $f) {
    $name = basename($f);
    copy($f, $dir . '/files/' . $name);
    $names[] = $name;
}
$limit = function ($s, $n) {
    $s = trim((string) $s);
    return function_exists('mb_substr') ? mb_substr($s, 0, $n) : substr($s, 0, $n);
};
$report = bys_read_json(bys_check_dir($ref) . '/report.json') ?? [];
bys_write_json($dir . '/request.json', [
    'reference' => $ref,
    'received_at' => date('c'),
    'source' => 'website',
    'contact' => [
        'name' => $limit($c['name'] ?? '', 200),
        'email' => $limit($c['email'] ?? '', 200),
        'phone' => $limit($c['phone'] ?? '', 50),
        'signing_date' => $limit($c['signing_date'] ?? '', 100),
    ],
    'title' => $limit($meta['title'] ?? trim(($report['community'] ?? '') . ' · Site ' . ($report['site'] ?? ''), ' ·'), 200),
    'rating' => $limit($report['overall_rating'] ?? '', 20),
    'rating_reason' => $limit($report['overall_reason'] ?? '', 500),
    'files' => $names,
    'bytes' => array_sum(array_map('filesize', $files)),
]);
bys_log("$ref review request received from the website: " . count($names) . ' files');

$paid = bys_payment($ref) !== null;
$emailed = $paid ? bys_deliver_if_ready($ref) : false;
bys_json(200, ['ok' => true, 'paid' => $paid, 'emailed' => $emailed]);
