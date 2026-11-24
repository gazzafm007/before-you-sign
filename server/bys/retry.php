<?php
// Re-sends any request that is paid and uploaded but whose email failed.
// For a cPanel cron job only (it does nothing when opened in a browser):
//   */15 * * * * php /home/<cpanel user>/public_html/bys/retry.php
// It also clears uploaded documents older than keep_days (config.php),
// once they have been emailed to ARPRA.

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
define('BYS', 1);
require __DIR__ . '/lib.php';

require __DIR__ . '/check_lib.php';

// Checks the host could not keep running after the upload, and checks that
// stopped part-way.
foreach (glob(bys_dir('checks') . '/BYS-*', GLOB_ONLYDIR) ?: [] as $dir) {
    $ref = basename($dir);
    if (bys_ref($ref) === null) {
        continue;
    }
    $job = bys_job($ref);
    if ($job === null) {
        continue;
    }
    $age = time() - strtotime($job['updated_at'] ?? 'now');
    if (($job['status'] ?? '') === 'queued' && $age > 120) {
        bys_log("$ref starting queued check (cron)");
        bys_run_job($ref);
    } elseif (($job['status'] ?? '') === 'running' && $age > 600) {
        bys_job_update($ref, ['status' => 'error', 'error' => 'The check stopped before it finished. Please try again.']);
        bys_log("$ref check timed out (cron)");
    }
    // Free checks: delete the uploaded documents after keep_check_files_days;
    // the report is kept (keep_days) in case the buyer asks ARPRA to review it.
    $fileDays = (int) (bys_config()['keep_check_files_days'] ?? 7);
    $created = strtotime($job['created_at'] ?? 'now');
    if ($fileDays > 0 && time() - $created > $fileDays * 86400 && glob($dir . '/files/*')) {
        foreach (glob($dir . '/files/*') ?: [] as $f) {
            @unlink($f);
        }
        bys_log("$ref check documents deleted after $fileDays days");
    }
    $keep = (int) (bys_config()['keep_days'] ?? 90);
    if ($keep > 0 && time() - $created > $keep * 86400 && is_file($dir . '/report.json')) {
        @unlink($dir . '/report.json');
        bys_log("$ref check report deleted after $keep days");
    }
}

$keepDays = (int) (bys_config()['keep_days'] ?? 90);
foreach (glob(bys_dir('requests') . '/BYS-*', GLOB_ONLYDIR) ?: [] as $dir) {
    $ref = basename($dir);
    if (bys_ref($ref) === null) {
        continue;
    }
    $emailed = $dir . '/emailed.json';
    if (!is_file($emailed)) {
        if (bys_payment($ref) !== null && is_file($dir . '/request.json')) {
            bys_log("$ref retrying email (cron)");
            bys_deliver_if_ready($ref);
        }
        continue;
    }
    // Delete the stored documents once they are well past being needed.
    if ($keepDays > 0 && time() - filemtime($emailed) > $keepDays * 86400) {
        foreach (glob($dir . '/files/*') ?: [] as $f) {
            @unlink($f);
        }
        @rmdir($dir . '/files');
        bys_log("$ref stored documents deleted after $keepDays days");
    }
}
