<?php
// Before You Sign — running the document check on ARPRA's server, so the
// Claude API key never leaves the server. Included by analyse.php,
// status.php, request.php and retry.php. Not callable from the web.

if (!defined('BYS')) {
    http_response_code(404);
    exit;
}

function bys_check_dir(string $ref): string
{
    return bys_dir('checks') . '/' . $ref;
}

function bys_job(string $ref): ?array
{
    return bys_read_json(bys_check_dir($ref) . '/job.json');
}

function bys_job_update(string $ref, array $changes): void
{
    $file = bys_check_dir($ref) . '/job.json';
    $job = bys_read_json($file) ?? [];
    bys_write_json($file, array_merge($job, $changes, ['updated_at' => date('c')]));
}

/** The prompt files live in prompt/ beside this file (generated from the app). */
function bys_prompt(): array
{
    $dir = __DIR__ . '/prompt';
    $system = @file_get_contents($dir . '/system.txt');
    if ($system === false || trim($system) === '') {
        throw new RuntimeException('prompt/system.txt is missing on the server');
    }
    $version = trim((string) @file_get_contents($dir . '/version.txt'));
    return [$system, $version];
}

/** The closing instruction for a check, from the buyer's details (website). */
function bys_build_instruction(array $d, array $labels): string
{
    $clean = function ($s, $n) {
        $s = trim(preg_replace('/\s+/', ' ', (string) $s));
        return function_exists('mb_substr') ? mb_substr($s, 0, $n) : substr($s, 0, $n);
    };
    $lines = ["Today's date is " . date('j F Y') . '.', 'The documents attached above, in order, are:'];
    foreach ($labels as $l) {
        $lines[] = '- ' . $l;
    }
    $community = $clean($d['community'] ?? '', 120);
    $site = $clean($d['site'] ?? '', 30);
    $buyer = $clean($d['buyer'] ?? '', 120);
    $notes = $clean($d['notes'] ?? '', 1000);
    if ($community !== '') {
        $lines[] = "Community (as told by the buyer): $community";
    }
    if ($site !== '') {
        $lines[] = "Site number (as told by the buyer): $site";
    }
    if ($buyer !== '') {
        $lines[] = "Buyer name(s): $buyer";
    }
    if ($notes !== '') {
        $lines[] = "Notes from the buyer: $notes";
    }
    $lines[] = '';
    $lines[] = 'Check these documents following your instructions and reply with the JSON object only.';
    return implode("\n", $lines);
}

/** Checks a Cloudflare Turnstile token (the website's "not a robot" check). */
function bys_turnstile_ok(string $token): bool
{
    $secret = (string) (bys_config()['turnstile_secret'] ?? '');
    if ($secret === '') {
        bys_log('WARNING: website check accepted without Turnstile (turnstile_secret is empty)');
        return true;
    }
    if ($token === '') {
        return false;
    }
    $ch = curl_init('https://challenges.cloudflare.com/turnstile/v0/siteverify');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query(['secret' => $secret, 'response' => $token, 'remoteip' => bys_client_ip()]),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
    ]);
    $out = curl_exec($ch);
    curl_close($ch);
    $j = json_decode((string) $out, true);
    return !empty($j['success']);
}

/** Counts how many checks a device, and the whole service, have run today. */
function bys_rate_ok(string $device, string $ip = ''): ?string
{
    $cfg = bys_config();
    $file = bys_dir() . '/usage-' . date('Y-m-d') . '.json';
    $fh = fopen($file, 'c+');
    if (!$fh) {
        return null;
    }
    flock($fh, LOCK_EX);
    $u = json_decode((string) stream_get_contents($fh), true) ?: ['total' => 0, 'devices' => []];
    $perDevice = (int) ($cfg['max_checks_per_device_per_day'] ?? 3);
    $perDay = (int) ($cfg['max_checks_per_day'] ?? 50);
    $mine = (int) ($u['devices'][$device] ?? 0);
    $perIp = (int) ($cfg['max_checks_per_ip_per_day'] ?? 3);
    $ipKey = $ip === '' ? '' : 'ip-' . hash('sha256', $ip);
    $fromIp = $ipKey === '' ? 0 : (int) ($u['devices'][$ipKey] ?? 0);
    $err = null;
    if ($perDay > 0 && $u['total'] >= $perDay) {
        $err = 'The checking service is very busy today. Please try again tomorrow, or call ARPRA on 1300 798 399.';
    } elseif ($perDevice > 0 && $mine >= $perDevice) {
        $err = "This phone has already run $perDevice checks today. Please try again tomorrow, or call ARPRA on 1300 798 399.";
    } elseif ($ipKey !== '' && $perIp > 0 && $fromIp >= $perIp) {
        $err = "$perIp checks have already been run from this internet connection today. Please try again tomorrow, or call ARPRA on 1300 798 399.";
    } else {
        $u['total']++;
        $u['devices'][$device] = $mine + 1;
        if ($ipKey !== '') {
            $u['devices'][$ipKey] = $fromIp + 1;
        }
        ftruncate($fh, 0);
        rewind($fh);
        fwrite($fh, json_encode($u));
    }
    flock($fh, LOCK_UN);
    fclose($fh);
    return $err;
}

/**
 * Runs one check: builds the Claude request from the uploaded files and the
 * app's plan, streams the answer, and saves report.json. Safe to call twice:
 * a lock stops two runs of the same job.
 */
function bys_run_job(string $ref): void
{
    $dir = bys_check_dir($ref);
    $lock = fopen($dir . '/.run.lock', 'c');
    if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) {
        return; // already running
    }
    try {
        $job = bys_job($ref);
        if (!$job || !in_array($job['status'] ?? '', ['queued', 'running'], true)) {
            return;
        }
        @set_time_limit(900);
        bys_job_update($ref, ['status' => 'running', 'started_at' => date('c'), 'chars' => 0]);
        bys_log("$ref check started");

        $cfg = bys_config();
        [$system, $version] = bys_prompt();

        $content = [];
        foreach ($job['plan'] ?? [] as $part) {
            if (($part['type'] ?? '') === 'text') {
                $content[] = ['type' => 'text', 'text' => (string) $part['text']];
                continue;
            }
            $path = $dir . '/files/' . basename((string) ($part['file'] ?? ''));
            if (!is_file($path)) {
                throw new RuntimeException('a document file is missing on the server');
            }
            $data = base64_encode((string) file_get_contents($path));
            if (($part['media'] ?? '') === 'application/pdf') {
                $content[] = [
                    'type' => 'document',
                    'source' => ['type' => 'base64', 'media_type' => 'application/pdf', 'data' => $data],
                    'title' => mb_substr((string) ($part['title'] ?? 'Document'), 0, 200),
                ];
            } else {
                $content[] = ['type' => 'image', 'source' => ['type' => 'base64', 'media_type' => 'image/jpeg', 'data' => $data]];
            }
        }
        if (!$content) {
            throw new RuntimeException('nothing to check');
        }

        $body = [
            'model' => $cfg['claude_model'] ?? 'claude-opus-5-5',
            'max_tokens' => (int) ($cfg['claude_max_tokens'] ?? 32000),
            'stream' => true,
            'system' => [['type' => 'text', 'text' => $system, 'cache_control' => ['type' => 'ephemeral']]],
            'messages' => [['role' => 'user', 'content' => $content]],
        ];
        $text = bys_claude_stream($body, function (int $chars) use ($ref) {
            bys_job_update($ref, ['chars' => $chars]);
        });

        $report = bys_parse_report($text);
        $report['_prompt_version'] = $version;
        $report['_checked_on_server'] = true;
        bys_write_json($dir . '/report.json', $report);
        bys_job_update($ref, ['status' => 'done', 'finished_at' => date('c'), 'chars' => strlen($text)]);
        bys_log("$ref check done (" . strlen($text) . ' chars, prompt ' . $version . ')');
    } catch (Throwable $e) {
        bys_job_update($ref, ['status' => 'error', 'error' => bys_friendly_error($e->getMessage())]);
        bys_log("$ref check FAILED: " . $e->getMessage());
    } finally {
        flock($lock, LOCK_UN);
        fclose($lock);
    }
}

/** Calls the Claude Messages API with streaming and returns the text. */
function bys_claude_stream(array $body, callable $progress): string
{
    $cfg = bys_config();
    $key = (string) ($cfg['anthropic_api_key'] ?? '');
    if ($key === '' || strpos($key, 'REPLACE') !== false) {
        throw new RuntimeException('anthropic_api_key is not set in config.php');
    }
    $text = '';
    $buffer = '';
    $streamError = null;
    $lastSaved = 0.0;
    $httpBody = '';

    $ch = curl_init(rtrim((string) ($cfg['anthropic_base'] ?? 'https://api.anthropic.com'), '/') . '/v1/messages');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($body, JSON_UNESCAPED_SLASHES),
        CURLOPT_HTTPHEADER => [
            'x-api-key: ' . $key,
            'anthropic-version: 2023-06-01',
            'content-type: application/json',
        ],
        CURLOPT_CONNECTTIMEOUT => 30,
        CURLOPT_TIMEOUT => 840,
        CURLOPT_WRITEFUNCTION => function ($ch, $chunk) use (&$text, &$buffer, &$streamError, &$lastSaved, &$httpBody, $progress) {
            if ((int) curl_getinfo($ch, CURLINFO_HTTP_CODE) !== 200) {
                $httpBody .= $chunk;
                return strlen($chunk);
            }
            $buffer .= $chunk;
            while (($i = strpos($buffer, "\n")) !== false) {
                $line = trim(substr($buffer, 0, $i));
                $buffer = substr($buffer, $i + 1);
                if (strncmp($line, 'data:', 5) !== 0) {
                    continue;
                }
                $ev = json_decode(trim(substr($line, 5)), true);
                if (!is_array($ev)) {
                    continue;
                }
                if (($ev['type'] ?? '') === 'content_block_delta' && ($ev['delta']['type'] ?? '') === 'text_delta') {
                    $text .= $ev['delta']['text'];
                    if (microtime(true) - $lastSaved > 2) {
                        $lastSaved = microtime(true);
                        $progress(strlen($text));
                    }
                } elseif (($ev['type'] ?? '') === 'error') {
                    $streamError = (string) ($ev['error']['message'] ?? 'unknown error');
                }
            }
            return strlen($chunk);
        },
    ]);
    $ok = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($ok === false) {
        throw new RuntimeException("network: $err");
    }
    if ($code !== 200) {
        $j = json_decode($httpBody, true);
        throw new RuntimeException("http $code: " . ($j['error']['message'] ?? substr($httpBody, 0, 200)));
    }
    if ($streamError !== null) {
        throw new RuntimeException("stream: $streamError");
    }
    return $text;
}

function bys_parse_report(string $raw): array
{
    $s = strpos($raw, '{');
    $e = strrpos($raw, '}');
    if ($s === false || $e === false || $e <= $s) {
        throw new RuntimeException('format: the report came back in an unexpected format');
    }
    $j = json_decode(substr($raw, $s, $e - $s + 1), true);
    if (!is_array($j)) {
        throw new RuntimeException('format: the report came back incomplete');
    }
    return $j;
}

/** Turns an internal error into something a buyer can act on. */
function bys_friendly_error(string $m): string
{
    if (strpos($m, 'http 401') === 0 || strpos($m, 'anthropic_api_key') !== false) {
        return 'The checking service is not set up correctly. Please call ARPRA on 1300 798 399.';
    }
    if (strpos($m, 'http 429') === 0) {
        return 'The checking service is very busy or has reached its limit. Please try again later, or call ARPRA on 1300 798 399.';
    }
    if (strpos($m, 'http 413') === 0) {
        return 'The documents are too large to check in one go. Try PDFs instead of photos, or remove duplicate pages.';
    }
    if (strpos($m, 'http 529') === 0 || strpos($m, 'http 503') === 0 || strpos($m, 'http 500') === 0) {
        return 'The checking service is busy right now. Please try again in a few minutes.';
    }
    if (strpos($m, 'format:') === 0) {
        return 'The report came back incomplete. Please try again.';
    }
    return 'The check could not be completed. Please try again in a few minutes.';
}

/**
 * The free summary the app shows the public: rating, top issues, key dates,
 * the titles of items that may conflict with the law, and counts of the rest.
 */
function bys_report_summary(array $r): array
{
    $l = function ($v) {
        return is_array($v) ? array_values(array_filter($v, 'is_array')) : [];
    };
    $red = $l($r['red'] ?? []);
    $amber = $l($r['amber'] ?? []);
    $items = array_merge($red, $amber);
    $basis = function ($m) {
        return (string) ($m['basis'] ?? '');
    };
    $lawRed = array_values(array_filter($red, function ($m) use ($basis) {
        return $basis($m) === 'law';
    }));
    $count = function (string $b) use ($items, $basis) {
        return count(array_filter($items, function ($m) use ($b, $basis) {
            return $basis($m) === $b;
        }));
    };
    $changes = count(array_filter($l($r['standard_terms_changes'] ?? []), function ($m) {
        return in_array(strtolower((string) ($m['status'] ?? '')), ['changed', 'missing', 'added', 'old version'], true);
    }));
    $ticks = count(array_filter($l($r['tick_boxes'] ?? []), function ($m) {
        return ($m['status'] ?? '') !== 'ok';
    }));

    $out = [];
    foreach (['community', 'site', 'operator', 'buyer', 'overall_rating', 'overall_reason', 'summary',
        'top_issues', 'key_dates', 'documents_reviewed', 'documents_missing', '_prompt_version'] as $k) {
        if (array_key_exists($k, $r)) {
            $out[$k] = $r[$k];
        }
    }
    $out['red'] = array_map(function ($m) {
        return ['title' => $m['title'] ?? '', 'basis' => 'law', 'law' => $m['law'] ?? ''];
    }, $lawRed);
    $out['_summary_only'] = true;
    $out['_counts'] = [
        'more_items' => count($items) - count($lawRed),
        'unfair_terms' => $count('unfair_terms'),
        'unclear' => $count('unclear'),
        'know' => $count('know'),
        'blanks' => count($l($r['blanks'] ?? [])),
        'tick_problems' => $ticks,
        'term_changes' => $changes,
        'questions' => is_array($r['questions'] ?? null) ? count($r['questions']) : 0,
    ];
    return $out;
}

/** The full report as a self-contained HTML page, for ARPRA staff and the buyer's email. */
function bys_report_html(array $r, string $ref): string
{
    $e = function ($s) {
        return htmlspecialchars(is_scalar($s) ? (string) $s : '', ENT_QUOTES, 'UTF-8');
    };
    $l = function ($v) {
        return is_array($v) ? array_values($v) : [];
    };
    $labels = ['law' => 'Against the law', 'unfair_terms' => 'May be an unfair term', 'know' => 'Lawful – worth knowing', 'unclear' => 'Missing or unclear'];
    $items = function (string $title, $list, string $colour) use ($e, $l, $labels) {
        $list = $l($list);
        if (!$list) {
            return '';
        }
        $h = '<h2>' . $e($title) . ' (' . count($list) . ')</h2>';
        foreach ($list as $m) {
            if (!is_array($m)) {
                continue;
            }
            $basis = $labels[$m['basis'] ?? ''] ?? '';
            if ($basis !== '' && !empty($m['law'])) {
                $basis .= ' · ' . $m['law'];
            }
            $h .= '<div class="item" style="border-left-color:' . $colour . '"><b>' . $e($m['title'] ?? '') . '</b>';
            if ($basis !== '') {
                $h .= '<div class="basis" style="color:' . $colour . '">' . $e($basis) . '</div>';
            }
            foreach (['detail' => '', 'where' => 'Where: ', 'ask' => 'Ask: '] as $k => $p) {
                if (!empty($m[$k])) {
                    $h .= '<div class="' . $k . '">' . $e($p . $m[$k]) . '</div>';
                }
            }
            $h .= '</div>';
        }
        return $h;
    };
    $table = function (array $head, array $rows) use ($e) {
        if (!$rows) {
            return '';
        }
        $h = '<table>';
        if (implode('', $head) !== '') {
            $h .= '<tr>' . implode('', array_map(function ($x) use ($e) {
                return '<th>' . $e($x) . '</th>';
            }, $head)) . '</tr>';
        }
        foreach ($rows as $row) {
            $h .= '<tr>' . implode('', array_map(function ($x) use ($e) {
                return '<td>' . $e($x) . '</td>';
            }, $row)) . '</tr>';
        }
        return $h . '</table>';
    };

    $c = is_array($r['costs'] ?? null) ? $r['costs'] : [];
    $h = '<!DOCTYPE html><html lang="en-AU"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>Before You Sign report ' . $e($ref) . '</title><style>'
        . 'body{font-family:Arial,Helvetica,sans-serif;color:#1a1c24;max-width:820px;margin:0 auto;padding:20px;line-height:1.45;font-size:16px}'
        . 'h1{color:#1500FE;font-size:24px;margin:0 0 4px}h2{font-size:19px;margin:26px 0 8px;border-bottom:1px solid #dadce3;padding-bottom:4px}'
        . '.muted{color:#555;font-size:14px}.box{background:#eef0fb;border-radius:8px;padding:12px 14px;margin:12px 0}'
        . '.item{border-left:4px solid #999;background:#fafafa;padding:8px 12px;margin:8px 0}.basis{font-size:13px;font-weight:bold}'
        . '.where{color:#555;font-size:14px}.ask{font-style:italic}table{border-collapse:collapse;width:100%;font-size:14px;margin:6px 0}'
        . 'th,td{border:1px solid #dadce3;padding:6px;text-align:left;vertical-align:top}th{background:#eef0fb}'
        . '</style></head><body>';
    $h .= '<h1>Before You Sign – full report</h1>';
    $h .= '<div class="muted">' . $e(trim(($r['community'] ?? '') . ' · Site ' . ($r['site'] ?? ''), ' ·')) . ' · Reference ' . $e($ref)
        . (!empty($r['_prompt_version']) ? ' · checker ' . $e($r['_prompt_version']) : '') . '</div>';
    $h .= '<div class="box"><b>Overall: ' . $e($r['overall_rating'] ?? '') . '</b> — ' . $e($r['overall_reason'] ?? '')
        . '<p>' . $e($r['summary'] ?? '') . '</p></div>';
    if ($l($r['top_issues'] ?? [])) {
        $h .= '<h2>The things that matter most</h2><ol>';
        foreach ($l($r['top_issues']) as $m) {
            $m = is_array($m) ? $m : ['title' => $m];
            $h .= '<li><b>' . $e($m['title'] ?? '') . '</b>' . (!empty($m['why']) ? '<br>' . $e($m['why']) : '')
                . (!empty($m['ask']) ? '<br><i>Ask: ' . $e($m['ask']) . '</i>' : '') . '</li>';
        }
        $h .= '</ol>';
    }
    $h .= '<h2>What it will cost</h2>' . $table(['', ''], array_values(array_filter([
        ['Proposed site fee', $c['proposed_fee'] ?? ''],
        ['Current fee for site', $c['current_fee'] ?? ''],
        ['Range in community', $c['community_range'] ?? ''],
        ['Increase method', $c['increase_method'] ?? ''],
        ['First increase', $c['first_increase'] ?? ''],
    ], function ($row) {
        return $row[1] !== '';
    })));
    $h .= $table(['When', 'Weekly site fee'], array_map(function ($m) {
        return [$m['when'] ?? '', $m['weekly'] ?? ''];
    }, array_filter($l($c['projection'] ?? []), 'is_array')));
    if ($l($c['other_costs'] ?? [])) {
        $h .= '<ul>' . implode('', array_map(function ($x) use ($e) {
            return '<li>' . $e($x) . '</li>';
        }, $l($c['other_costs']))) . '</ul>';
    }
    if ($l($r['key_dates'] ?? [])) {
        $h .= '<h2>Key dates</h2>' . $table(['Date', 'What'], array_map(function ($m) {
            return [$m['date'] ?? '', $m['what'] ?? ''];
        }, array_filter($l($r['key_dates']), 'is_array')));
    }
    $h .= $items('Look closely before you sign', $r['red'] ?? [], '#B3261E');
    $h .= $items('Ask about', $r['amber'] ?? [], '#8A5300');
    $h .= $items('Looks usual', $r['green'] ?? [], '#1E6B3A');
    if ($l($r['standard_terms_changes'] ?? [])) {
        $h .= '<h2>Changes to the standard terms</h2>' . $table(['Clause', 'Standard form says', 'This agreement says', 'Effect'],
            array_map(function ($m) {
                return [trim(($m['clause'] ?? '') . ' ' . ($m['status'] ?? '')), $m['prescribed'] ?? '', $m['document_says'] ?? '', $m['effect'] ?? ''];
            }, array_filter($l($r['standard_terms_changes']), 'is_array')));
    }
    if ($l($r['tick_boxes'] ?? [])) {
        $h .= '<h2>Tick-boxes</h2>' . $table(['Where', 'Box group', 'Marked', 'Check'], array_map(function ($m) {
            $st = $m['status'] ?? '';
            return [trim(($m['document'] ?? '') . ' p ' . ($m['page'] ?? ''), ' p'), $m['group'] ?? '', $m['ticked'] ?? '',
                $st === 'ok' ? 'OK' : trim($st . ': ' . ($m['issue'] ?? ''), ': ')];
        }, array_filter($l($r['tick_boxes']), 'is_array')));
    }
    if ($l($r['blanks'] ?? [])) {
        $h .= '<h2>Blank or incomplete</h2><ul>';
        foreach (array_filter($l($r['blanks']), 'is_array') as $m) {
            $h .= '<li><b>' . $e($m['field'] ?? '') . '</b> — ' . $e(trim(($m['document'] ?? '') . ', p ' . ($m['page'] ?? ''), ', p'))
                . (!empty($m['why']) ? '. ' . $e($m['why']) : '') . '</li>';
        }
        $h .= '</ul>';
    }
    if ($l($r['questions'] ?? [])) {
        $h .= '<h2>Questions to ask</h2><ol>' . implode('', array_map(function ($x) use ($e) {
            return '<li>' . $e($x) . '</li>';
        }, $l($r['questions']))) . '</ol>';
    }
    $h .= '<h2>Documents checked</h2><ul>';
    foreach (array_filter($l($r['documents_reviewed'] ?? []), 'is_array') as $m) {
        $h .= '<li>' . $e(implode(' — ', array_filter([$m['name'] ?? '', $m['date'] ?? '', $m['notes'] ?? '']))) . '</li>';
    }
    $h .= '</ul>';
    if ($l($r['documents_missing'] ?? [])) {
        $h .= '<p class="muted">Not provided: ' . $e(implode('; ', array_map('strval', $l($r['documents_missing'])))) . '</p>';
    }
    $h .= '<p class="muted">This report was prepared by an automated first check and is reviewed by an ARPRA adviser as part of '
        . 'ARPRA\'s pre-purchase service. It is not legal or financial advice. ARPRA Limited · 1300 798 399</p></body></html>';
    return $h;
}
