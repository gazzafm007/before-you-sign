<?php
// The app follows a check: GET status.php?ref=BYS-1A2B3C4D (header X-BYS-Key).
// Reply: {"status":"queued"|"running"|"done"|"error","chars":n,"error":…,"report":{…}}
// When done, "report" is the full report or the free summary, depending on
// report_to_app in config.php.

define('BYS', 1);
require __DIR__ . '/lib.php';
require __DIR__ . '/check_lib.php';

bys_require_app_key();
$ref = bys_ref($_GET['ref'] ?? '');
if ($ref === null) {
    bys_json(400, ['error' => 'Bad reference']);
}
$job = bys_job($ref);
if ($job === null) {
    bys_json(404, ['status' => 'missing', 'error' => 'No check found for this reference.']);
}
$device = preg_replace('/[^A-Za-z0-9-]/', '', (string) ($_SERVER['HTTP_X_BYS_DEVICE'] ?? ''));
if ($device === '' || !hash_equals((string) ($job['device'] ?? ''), $device)) {
    bys_json(403, ['error' => 'Not allowed.']);
}

$status = (string) ($job['status'] ?? 'queued');
$age = time() - strtotime($job['updated_at'] ?? 'now');
// A check that never started (the host could not keep it running after the
// upload): start it now, while the app is waiting.
if ($status === 'queued' && $age > 20) {
    ignore_user_abort(true);
    bys_run_job($ref);
    $job = bys_job($ref) ?? $job;
    $status = (string) ($job['status'] ?? 'queued');
}
// A check that stopped without finishing.
if ($status === 'running' && $age > 600) {
    bys_job_update($ref, ['status' => 'error', 'error' => 'The check stopped before it finished. Please try again.']);
    bys_log("$ref check timed out");
    $status = 'error';
    $job['error'] = 'The check stopped before it finished. Please try again.';
}

$out = ['ref' => $ref, 'status' => $status, 'chars' => (int) ($job['chars'] ?? 0)];
if ($status === 'error') {
    $out['error'] = (string) ($job['error'] ?? 'The check could not be completed.');
}
if ($status === 'done') {
    $report = bys_read_json(bys_check_dir($ref) . '/report.json');
    if ($report === null) {
        bys_json(500, ['status' => 'error', 'error' => 'The report could not be read. Please try again.']);
    }
    $full = (bys_config()['report_to_app'] ?? 'summary') === 'full';
    $out['report'] = $full ? $report : bys_report_summary($report);
}
bys_json(200, $out);
