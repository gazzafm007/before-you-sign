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
