<?php
// The app uploads the buyer's documents for an ARPRA review.
// POST multipart/form-data (header X-BYS-Key: <app_key>):
//   ref      BYS-1A2B3C4D
//   meta     JSON: {"contact":{name,email,phone,signing_date},"title","rating","rating_reason"}
//   files[]  PDFs (report and documents) and one .json case file
// The files are stored outside public_html. They are emailed to ARPRA as soon
// as Stripe has confirmed payment (now, or later from the webhook).
// Reply: {"ok":true,"ref":…,"paid":bool,"emailed":bool}

define('BYS', 1);
require __DIR__ . '/lib.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bys_json(405, ['error' => 'POST only']);
}
bys_require_app_key();
$cfg = bys_config();

// An upload bigger than PHP's post_max_size arrives with empty $_POST.
if (empty($_POST) && (int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 0) {
    bys_json(413, ['error' => 'Upload too large for the server.']);
}

$ref = bys_ref($_POST['ref'] ?? '');
if ($ref === null) {
    bys_json(400, ['error' => 'Bad reference']);
}
$meta = json_decode((string) ($_POST['meta'] ?? ''), true);
if (!is_array($meta)) {
    bys_json(400, ['error' => 'Missing details']);
}

$dir = bys_request_dir($ref);
if (is_file($dir . '/emailed.json')) {
    bys_json(200, ['ok' => true, 'ref' => $ref, 'paid' => true, 'emailed' => true, 'note' => 'Already sent to ARPRA.']);
}

$up = $_FILES['files'] ?? null;
if (!$up || !is_array($up['name'])) {
    bys_json(400, ['error' => 'No files']);
}
$count = count($up['name']);
if ($count < 1 || $count > 40) {
    bys_json(400, ['error' => 'Between 1 and 40 files, please.']);
}
$total = array_sum($up['size']);
if ($total > ((float) $cfg['max_upload_mb']) * 1048576) {
    bys_json(413, ['error' => 'Upload too large.']);
}

// Check every file before saving any of them.
$accepted = [];
for ($i = 0; $i < $count; $i++) {
    if ($up['error'][$i] !== UPLOAD_ERR_OK) {
        bys_json(400, ['error' => 'A file did not upload (code ' . $up['error'][$i] . ').']);
    }
    $name = preg_replace('/[^A-Za-z0-9._-]+/', '_', basename((string) $up['name'][$i]));
    $name = ltrim($name, '.');
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    $tmp = $up['tmp_name'][$i];
    $head = (string) file_get_contents($tmp, false, null, 0, 5);
    if ($ext === 'pdf' && $head === '%PDF-') {
        // ok
    } elseif ($ext === 'json' && is_array(json_decode((string) file_get_contents($tmp), true))) {
        // ok
    } else {
        bys_json(415, ['error' => "Only PDF and JSON files are accepted ($name)."]);
    }
    if ($name === '' || isset($accepted[$name])) {
        $name = sprintf('%02d_%s', $i + 1, $name === '' ? "file.$ext" : $name);
    }
    $accepted[$name] = $tmp;
}

// Replace any earlier, unsent upload for this case.
$filesDir = $dir . '/files';
if (is_dir($filesDir)) {
    foreach (glob($filesDir . '/*') ?: [] as $old) {
        @unlink($old);
    }
} elseif (!mkdir($filesDir, 0700, true) && !is_dir($filesDir)) {
    bys_json(500, ['error' => 'Cannot store files.']);
}
foreach ($accepted as $name => $tmp) {
    if (!move_uploaded_file($tmp, $filesDir . '/' . $name)) {
        bys_json(500, ['error' => 'Cannot store files.']);
    }
}

$limit = function ($s, $n) {
    $s = trim((string) $s);
    return function_exists('mb_substr') ? mb_substr($s, 0, $n) : substr($s, 0, $n);
};
$c = is_array($meta['contact'] ?? null) ? $meta['contact'] : [];
bys_write_json($dir . '/request.json', [
    'reference' => $ref,
    'received_at' => date('c'),
    'contact' => [
        'name' => $limit($c['name'] ?? '', 200),
        'email' => $limit($c['email'] ?? '', 200),
        'phone' => $limit($c['phone'] ?? '', 50),
        'signing_date' => $limit($c['signing_date'] ?? '', 100),
    ],
    'title' => $limit($meta['title'] ?? '', 200),
    'rating' => $limit($meta['rating'] ?? '', 20),
    'rating_reason' => $limit($meta['rating_reason'] ?? '', 500),
    'files' => array_keys($accepted),
    'bytes' => $total,
]);
bys_log("$ref request received: " . count($accepted) . ' files, ' . round($total / 1048576, 1) . ' MB');

$paid = bys_payment($ref) !== null;
$emailed = $paid ? bys_deliver_if_ready($ref) : false;

bys_json(200, ['ok' => true, 'ref' => $ref, 'paid' => $paid, 'emailed' => $emailed]);
