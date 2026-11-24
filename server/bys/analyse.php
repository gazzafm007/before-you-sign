<?php
// The app uploads a buyer's documents to be checked. The server runs the
// check with ARPRA's Claude key (never sent to phones) and the app follows
// progress with status.php.
//
// POST multipart/form-data (header X-BYS-Key: <app_key>):
//   ref     BYS-1A2B3C4D (the case reference)
//   device  random id the app keeps per install (for daily limits)
//   plan    JSON list, in order: {"type":"text","text":…} or
//           {"type":"file","file":"<name in files[]>","media":"image/jpeg"|"application/pdf","title":…}
//   files[] the photos (JPEG) and PDFs named in the plan
// Reply: {"ok":true,"ref":…,"status":"queued"|"running"|"done"|"error"}

define('BYS', 1);
require __DIR__ . '/lib.php';
require __DIR__ . '/check_lib.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bys_json(405, ['error' => 'POST only']);
}
bys_require_app_key();
$cfg = bys_config();

if (empty($_POST) && (int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 0) {
    bys_json(413, ['error' => 'The documents are too large to send in one go. Try PDFs instead of photos, or remove duplicate pages.']);
}
$ref = bys_ref($_POST['ref'] ?? '');
if ($ref === null) {
    bys_json(400, ['error' => 'Bad reference']);
}
$device = preg_replace('/[^A-Za-z0-9-]/', '', (string) ($_POST['device'] ?? ''));
if (strlen($device) < 8) {
    bys_json(400, ['error' => 'Missing device id']);
}
$plan = json_decode((string) ($_POST['plan'] ?? ''), true);
if (!is_array($plan) || !$plan) {
    bys_json(400, ['error' => 'Missing plan']);
}

// A check for this case already under way: just report its status.
$existing = bys_job($ref);
if ($existing && in_array($existing['status'] ?? '', ['queued', 'running'], true)
    && time() - strtotime($existing['updated_at'] ?? 'now') < 900) {
    bys_json(200, ['ok' => true, 'ref' => $ref, 'status' => $existing['status']]);
}

// Files: PDFs and JPEGs only, every one named in the plan.
$up = $_FILES['files'] ?? null;
$names = [];
if ($up && is_array($up['name'])) {
    $count = count($up['name']);
    if ($count > 120) {
        bys_json(400, ['error' => 'Too many pages for one check (the limit is 100 photographed pages).']);
    }
    if (array_sum($up['size']) > ((float) ($cfg['max_upload_mb'] ?? 60)) * 1048576) {
        bys_json(413, ['error' => 'The documents are too large to send in one go. Try PDFs instead of photos, or remove duplicate pages.']);
    }
    for ($i = 0; $i < $count; $i++) {
        if ($up['error'][$i] !== UPLOAD_ERR_OK) {
            bys_json(400, ['error' => 'A page did not upload. Please try again.']);
        }
        $name = basename((string) $up['name'][$i]);
        if (!preg_match('/^[A-Za-z0-9_.-]{1,80}$/', $name)) {
            bys_json(400, ['error' => 'Bad file name']);
        }
        $head = (string) file_get_contents($up['tmp_name'][$i], false, null, 0, 5);
        $isPdf = $head === '%PDF-';
        $isJpeg = substr($head, 0, 3) === "\xFF\xD8\xFF";
        if (!$isPdf && !$isJpeg) {
            bys_json(415, ['error' => 'Only photos and PDF files can be checked.']);
        }
        $names[$name] = $i;
    }
}
$images = 0;
foreach ($plan as $p) {
    if (($p['type'] ?? '') === 'file') {
        if (!isset($names[$p['file'] ?? ''])) {
            bys_json(400, ['error' => 'A document is missing from the upload. Please try again.']);
        }
        if (($p['media'] ?? '') !== 'application/pdf') {
            $images++;
        }
    } elseif (($p['type'] ?? '') !== 'text') {
        bys_json(400, ['error' => 'Bad plan']);
    }
}
if ($images > 100) {
    bys_json(400, ['error' => "That is $images photographed pages; the limit for one check is 100. If you have the documents as PDFs, add those instead."]);
}

$limit = bys_rate_ok($device);
if ($limit !== null) {
    bys_json(429, ['error' => $limit]);
}

// Store everything, replacing any earlier check of this case.
$dir = bys_check_dir($ref);
if (!is_dir($dir . '/files') && !mkdir($dir . '/files', 0700, true) && !is_dir($dir . '/files')) {
    bys_json(500, ['error' => 'Cannot store files.']);
}
foreach (glob($dir . '/files/*') ?: [] as $old) {
    @unlink($old);
}
@unlink($dir . '/report.json');
foreach ($names as $name => $i) {
    if (!move_uploaded_file($up['tmp_name'][$i], $dir . '/files/' . $name)) {
        bys_json(500, ['error' => 'Cannot store files.']);
    }
}
bys_write_json($dir . '/job.json', [
    'reference' => $ref,
    'device' => $device,
    'status' => 'queued',
    'created_at' => date('c'),
    'updated_at' => date('c'),
    'plan' => $plan,
    'chars' => 0,
]);
bys_log("$ref check queued: " . count($names) . ' files');

// Answer the app now, then keep running the check after the connection
// closes (PHP-FPM or LiteSpeed). If neither is available the check runs
// before the reply; the app follows progress with status.php either way,
// and retry.php's cron job picks up any check that never started.
ignore_user_abort(true);
@set_time_limit(900);
$reply = json_encode(['ok' => true, 'ref' => $ref, 'status' => 'queued']);
http_response_code(200);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
if (function_exists('fastcgi_finish_request')) {
    echo $reply;
    fastcgi_finish_request();
} elseif (function_exists('litespeed_finish_request')) {
    echo $reply;
    litespeed_finish_request();
} else {
    header('Connection: close');
    header('Content-Length: ' . strlen($reply));
    echo $reply;
    while (ob_get_level() > 0) {
        ob_end_flush();
    }
    flush();
}
bys_run_job($ref);
