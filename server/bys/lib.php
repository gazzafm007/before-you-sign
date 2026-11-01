<?php
// Shared helpers for the Before You Sign server scripts. Not callable from the
// web (blocked in .htaccess and guarded below).

if (!defined('BYS')) {
    http_response_code(404);
    exit;
}

date_default_timezone_set('Australia/Sydney');

function bys_config(): array
{
    static $cfg = null;
    if ($cfg === null) {
        $file = __DIR__ . '/config.php';
        if (!is_file($file)) {
            bys_json(500, ['error' => 'Server not set up (config.php missing).']);
        }
        $cfg = require $file;
    }
    return $cfg;
}

function bys_json(int $code, array $data): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($data, JSON_UNESCAPED_SLASHES);
    exit;
}

function bys_dir(string $sub = ''): string
{
    $base = rtrim(bys_config()['data_dir'], '/');
    $d = $sub === '' ? $base : $base . '/' . $sub;
    if (!is_dir($d) && !mkdir($d, 0700, true) && !is_dir($d)) {
        bys_json(500, ['error' => 'Cannot create the data folder.']);
    }
    return $d;
}

function bys_log(string $msg): void
{
    @file_put_contents(bys_dir() . '/bys.log', date('c') . ' ' . $msg . "\n", FILE_APPEND | LOCK_EX);
}

/** Case references look like BYS-1A2B3C4D. Returns the reference or null. */
function bys_ref($v): ?string
{
    $v = strtoupper(trim((string) $v));
    return preg_match('/^BYS-[A-F0-9]{8}$/', $v) ? $v : null;
}

/** Rejects requests that do not carry the app's shared key. */
function bys_require_app_key(): void
{
    $sent = $_SERVER['HTTP_X_BYS_KEY'] ?? '';
    $key = (string) bys_config()['app_key'];
    if ($key === '' || strpos($key, 'REPLACE') !== false || !hash_equals($key, (string) $sent)) {
        bys_json(403, ['error' => 'Not allowed.']);
    }
}

function bys_read_json(string $file): ?array
{
    if (!is_file($file)) {
        return null;
    }
    $d = json_decode((string) file_get_contents($file), true);
    return is_array($d) ? $d : null;
}

function bys_write_json(string $file, array $data): void
{
    $tmp = $file . '.tmp' . bin2hex(random_bytes(4));
    file_put_contents($tmp, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    rename($tmp, $file);
}

function bys_payment(string $ref): ?array
{
    return bys_read_json(bys_dir('payments') . '/' . $ref . '.json');
}

function bys_request_dir(string $ref): string
{
    return bys_dir('requests') . '/' . $ref;
}

/**
 * Emails a stored request to ARPRA once it is both uploaded and paid.
 * Safe to call more than once: a lock and a marker file make sure it is only
 * ever sent one time.
 */
function bys_deliver_if_ready(string $ref): bool
{
    $dir = bys_request_dir($ref);
    $meta = bys_read_json($dir . '/request.json');
    $pay = bys_payment($ref);
    if ($meta === null || $pay === null) {
        return false;
    }
    $lock = fopen($dir . '/.lock', 'c');
    if (!$lock || !flock($lock, LOCK_EX)) {
        return false;
    }
    try {
        if (is_file($dir . '/emailed.json')) {
            return true;
        }
        $ok = bys_send_request_email($ref, $meta, $pay, $dir);
        if ($ok) {
            bys_write_json($dir . '/emailed.json', ['emailed_at' => date('c'), 'to' => bys_config()['mail_to']]);
            bys_log("$ref emailed to " . bys_config()['mail_to']);
        } else {
            bys_log("$ref email FAILED");
        }
        return $ok;
    } finally {
        flock($lock, LOCK_UN);
        fclose($lock);
    }
}

function bys_send_request_email(string $ref, array $meta, array $pay, string $dir): bool
{
    $cfg = bys_config();
    $graph = ($cfg['mail_method'] ?? 'php') === 'graph';
    $contact = $meta['contact'] ?? [];
    $clean = function ($s) {
        return trim(preg_replace('/[\r\n]+/', ' ', (string) $s));
    };

    $files = [];
    foreach ($meta['files'] ?? [] as $name) {
        $p = $dir . '/files/' . basename($name);
        if (is_file($p)) {
            $files[] = $p;
        }
    }
    $total = 0;
    foreach ($files as $p) {
        $total += filesize($p);
    }
    // Microsoft 365 takes up to 150 MB a message; plain PHP mail is kept small.
    $limit = $graph ? 140 * 1048576 : ((float) $cfg['max_email_mb']) * 1048576 * 0.72; // base64 adds a third
    $attach = $total <= $limit;

    $amount = isset($pay['amount_total']) ? number_format($pay['amount_total'] / 100, 2) . ' ' . strtoupper($pay['currency'] ?? '') : 'unknown';
    $lines = [
        "Pre-purchase review request $ref",
        '',
        'PAYMENT CONFIRMED BY STRIPE' . (empty($pay['livemode']) ? ' (TEST / SANDBOX PAYMENT)' : ''),
        "Amount: $amount",
        'Stripe session: ' . ($pay['session_id'] ?? ''),
        'Paid at: ' . ($pay['paid_at'] ?? ''),
        '',
        'Name: ' . $clean($contact['name'] ?? ''),
        'Email: ' . $clean($contact['email'] ?? ''),
        'Phone: ' . $clean($contact['phone'] ?? ''),
        'Planning to sign around: ' . ($clean($contact['signing_date'] ?? '') ?: 'not stated'),
        'Community / site: ' . $clean($meta['title'] ?? ''),
        'Includes: 12 months ARPRA membership',
        '',
        'App check: ' . $clean($meta['rating'] ?? 'not run') . ' – ' . $clean($meta['rating_reason'] ?? ''),
        '',
    ];
    if ($attach) {
        $lines[] = 'Attached: the app report (PDF), each document, and the case data (JSON).';
    } else {
        $lines[] = 'The documents were too large to attach (' . round($total / 1048576, 1) . ' MB).';
        $lines[] = 'They are on the web server in bys-data/requests/' . $ref . '/files/';
        $lines[] = '(cPanel → File Manager). Files:';
        foreach ($files as $p) {
            $lines[] = ' - ' . basename($p);
        }
    }
    $lines[] = '';
    $lines[] = 'Received from the Before You Sign app on ' . ($meta['received_at'] ?? date('c')) . '.';
    $body = implode("\r\n", $lines);
    $subject = 'Pre-purchase review request ' . $ref . ' – ' . $clean($meta['title'] ?? '');
    $replyTo = $clean($contact['email'] ?? '');
    if (!filter_var($replyTo, FILTER_VALIDATE_EMAIL)) {
        $replyTo = '';
    }
    $files = $attach ? $files : [];

    if ($graph) {
        try {
            bys_graph_send($cfg['mail_to'], $subject, $body, $files, $replyTo);
            return true;
        } catch (Throwable $e) {
            bys_log("$ref Microsoft 365 send failed: " . $e->getMessage());
            return false;
        }
    }
    return bys_php_mail($cfg['mail_to'], $subject, $body, $files, $replyTo);
}

/** Sends with the hosting server's own mail (PHP mail()). */
function bys_php_mail(string $to, string $subject, string $body, array $files, string $replyTo): bool
{
    $from = bys_config()['mail_from'];
    $headers = ['From: Before You Sign <' . $from . '>', 'MIME-Version: 1.0'];
    if ($replyTo !== '') {
        $headers[] = 'Reply-To: ' . $replyTo;
    }
    if ($files) {
        $b = 'bys_' . bin2hex(random_bytes(8));
        $headers[] = 'Content-Type: multipart/mixed; boundary="' . $b . '"';
        $msg = "--$b\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            . chunk_split(base64_encode($body)) . "\r\n";
        foreach ($files as $p) {
            $name = basename($p);
            $type = bys_mime($name);
            $msg .= "--$b\r\nContent-Type: $type; name=\"$name\"\r\nContent-Transfer-Encoding: base64\r\n"
                . "Content-Disposition: attachment; filename=\"$name\"\r\n\r\n"
                . chunk_split(base64_encode((string) file_get_contents($p))) . "\r\n";
        }
        $msg .= "--$b--\r\n";
    } else {
        $headers[] = 'Content-Type: text/plain; charset=UTF-8';
        $headers[] = 'Content-Transfer-Encoding: base64';
        $msg = chunk_split(base64_encode($body));
    }
    $subject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    return mail($to, $subject, $msg, implode("\r\n", $headers), '-f' . $from);
}

function bys_mime(string $name): string
{
    return strtolower(substr($name, -5)) === '.json' ? 'application/json' : 'application/pdf';
}

// ---------------------------------------------------------------------------
// Microsoft 365 (Microsoft Graph) sending, using an Entra app registration
// with the application permission Mail.Send. Sends from graph_sender (e.g. the
// prepurchase@ shared mailbox) and keeps a copy in its Sent Items.
// ---------------------------------------------------------------------------

function bys_http(string $method, string $url, array $headers, ?string $body): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 120,
        CURLOPT_CONNECTTIMEOUT => 20,
    ]);
    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }
    $out = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    if ($out === false) {
        throw new RuntimeException("network error: $err");
    }
    return [$code, (string) $out];
}

function bys_graph_token(): string
{
    $g = bys_config()['graph'] ?? [];
    $login = rtrim($g['login_base'] ?? 'https://login.microsoftonline.com', '/');
    [$code, $out] = bys_http('POST', "$login/" . rawurlencode($g['tenant_id'] ?? '') . '/oauth2/v2.0/token',
        ['Content-Type: application/x-www-form-urlencoded'],
        http_build_query([
            'client_id' => $g['client_id'] ?? '',
            'client_secret' => $g['client_secret'] ?? '',
            'scope' => 'https://graph.microsoft.com/.default',
            'grant_type' => 'client_credentials',
        ]));
    $j = json_decode($out, true);
    if ($code !== 200 || empty($j['access_token'])) {
        throw new RuntimeException("token request failed ($code): " . substr($out, 0, 300));
    }
    return $j['access_token'];
}

function bys_graph(string $token, string $method, string $path, ?array $json = null): array
{
    $g = bys_config()['graph'] ?? [];
    $base = rtrim($g['graph_base'] ?? 'https://graph.microsoft.com/v1.0', '/');
    [$code, $out] = bys_http($method, $base . $path,
        ['Authorization: Bearer ' . $token, 'Content-Type: application/json'],
        $json === null ? ($method === 'POST' ? '' : null) : json_encode($json, JSON_UNESCAPED_SLASHES));
    if ($code < 200 || $code >= 300) {
        throw new RuntimeException("$method $path failed ($code): " . substr($out, 0, 300));
    }
    $j = json_decode($out, true);
    return is_array($j) ? $j : [];
}

function bys_graph_send(string $to, string $subject, string $body, array $files, string $replyTo): void
{
    $g = bys_config()['graph'] ?? [];
    $sender = $g['sender'] ?? '';
    if ($sender === '' || empty($g['client_secret'])) {
        throw new RuntimeException('graph settings incomplete in config.php');
    }
    $token = bys_graph_token();
    $user = '/users/' . rawurlencode($sender);
    $message = [
        'subject' => $subject,
        'body' => ['contentType' => 'Text', 'content' => $body],
        'toRecipients' => [['emailAddress' => ['address' => $to]]],
    ];
    if ($replyTo !== '') {
        $message['replyTo'] = [['emailAddress' => ['address' => $replyTo]]];
    }
    $small = 3 * 1000 * 1000; // Graph takes attachments under 3 MB inline

    $total = 0;
    foreach ($files as $p) {
        $total += filesize($p);
    }
    if ($total < $small) {
        // Everything fits in one request.
        $message['attachments'] = array_map(function ($p) {
            return [
                '@odata.type' => '#microsoft.graph.fileAttachment',
                'name' => basename($p),
                'contentType' => bys_mime(basename($p)),
                'contentBytes' => base64_encode((string) file_get_contents($p)),
            ];
        }, $files);
        bys_graph($token, 'POST', "$user/sendMail", ['message' => $message, 'saveToSentItems' => true]);
        return;
    }

    // Large: make a draft, add each attachment (big ones in chunks), then send.
    $draft = bys_graph($token, 'POST', "$user/messages", $message);
    $id = rawurlencode($draft['id'] ?? '');
    if ($id === '') {
        throw new RuntimeException('draft not created');
    }
    foreach ($files as $p) {
        $name = basename($p);
        $size = filesize($p);
        if ($size < $small) {
            bys_graph($token, 'POST', "$user/messages/$id/attachments", [
                '@odata.type' => '#microsoft.graph.fileAttachment',
                'name' => $name,
                'contentType' => bys_mime($name),
                'contentBytes' => base64_encode((string) file_get_contents($p)),
            ]);
            continue;
        }
        $session = bys_graph($token, 'POST', "$user/messages/$id/attachments/createUploadSession", [
            'AttachmentItem' => ['attachmentType' => 'file', 'name' => $name, 'size' => $size, 'contentType' => bys_mime($name)],
        ]);
        $url = $session['uploadUrl'] ?? '';
        if ($url === '') {
            throw new RuntimeException("no upload session for $name");
        }
        $chunk = 320 * 1024 * 12; // 3.75 MB, a multiple of 320 KiB as Graph requires
        $fh = fopen($p, 'rb');
        for ($start = 0; $start < $size; $start += $chunk) {
            $data = fread($fh, $chunk);
            $end = $start + strlen($data) - 1;
            [$code, $out] = bys_http('PUT', $url, [
                'Content-Type: application/octet-stream',
                'Content-Length: ' . strlen($data),
                "Content-Range: bytes $start-$end/$size",
            ], $data);
            if ($code !== 200 && $code !== 201) {
                fclose($fh);
                throw new RuntimeException("upload of $name failed ($code): " . substr($out, 0, 300));
            }
        }
        fclose($fh);
    }
    bys_graph($token, 'POST', "$user/messages/$id/send", null);
}
