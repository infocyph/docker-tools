<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class LogParser
{
    /** @return list<array{ts:string,level:string,summary:string,body:string}> */
    public function parseEntries(string $text): array
    {
        $lines = preg_split("/\r\n|\n|\r/", $text) ?: [];
        $entries = [];
        $cur = null;

        $flush = static function () use (&$entries, &$cur): void {
            if (!$cur) return;
            $cur['body'] = rtrim((string)$cur['body']);
            $entries[] = $cur;
            $cur = null;
        };

        foreach ($lines as $line) {
            if ($line === '') continue;

            // Access logs detectors
            if (preg_match('~"\s*[A-Z]+\s+[^\"]+"\s+(\d{3})\b~', $line, $m)) {
                $code = (int)$m[1];
                $lvl = ($code >= 500) ? 'error' : (($code >= 400) ? 'warn' : 'info');
                $flush();
                $entries[] = ['ts'=>'','level'=>$lvl,'summary'=>mb_substr($line,0,220),'body'=>$line];
                continue;
            }

            if (
                preg_match('~\b(1\d{2}|2\d{2}|3\d{2}|4\d{2}|5\d{2})\b~', $line, $m)
                && (preg_match('~\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b~', $line) || str_contains($line, 'HTTP/'))
            ) {
                $code = (int)$m[1];
                $lvl = ($code >= 500) ? 'error' : (($code >= 400) ? 'warn' : 'info');
                $flush();
                $entries[] = ['ts'=>'','level'=>$lvl,'summary'=>mb_substr($line,0,220),'body'=>$line];
                continue;
            }

            // Laravel detector
            if (preg_match('~^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\]\s+([^.]+)\.([A-Z]+):\s*(.*)$~', $line, $m)) {
                $flush();
                $lvl = strtolower($m[4]);
                if ($lvl === 'warning') $lvl = 'warn';
                $cur = [
                    'ts'      => $m[1] . ' ' . $m[2],
                    'level'   => $lvl,
                    'summary' => ($m[5] !== '') ? $m[5] : '(no message)',
                    'body'    => $line . "\n",
                ];
                continue;
            }

            $isNew = false;
            $lvl = 'info';
            $ts = '';

            if (preg_match('~^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?\s+(DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL|FATAL)\b~i', $line, $m)) {
                $isNew = true;
                $ts = $m[1] . ' ' . $m[2];
                $lvl = strtolower($m[3]);
                if ($lvl === 'warning') $lvl = 'warn';
                if ($lvl === 'fatal' || $lvl === 'critical') $lvl = 'error';
            } elseif (preg_match('~^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.\d+)?Z?\s*(?:\[[A-Z]+\]\s*)?(ERROR|WARN|WARNING|INFO|DEBUG)\b~i', $line, $m)) {
                $isNew = true;
                $ts = $m[1] . ' ' . $m[2];
                $lvl = strtolower($m[3]);
                if ($lvl === 'warning') $lvl = 'warn';
            } elseif (preg_match('~^\[(\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}:\d{2})\]\s+~', $line, $m)) {
                $isNew = true;
                $ts = $m[1];
                $lvl = 'warn';
            } elseif (preg_match('~\b(FATAL|CRITICAL)\b~i', $line)) {
                $isNew = true; $lvl = 'error';
            } elseif (preg_match('~\b(WARN|WARNING)\b~i', $line)) {
                $isNew = true; $lvl = 'warn';
            }

            if ($isNew) {
                $flush();
                $cur = [
                    'ts'      => $ts,
                    'level'   => $lvl,
                    'summary' => mb_substr($line, 0, 220),
                    'body'    => $line . "\n",
                ];
            } else {
                if (!$cur) {
                    $cur = [
                        'ts'      => '',
                        'level'   => 'info',
                        'summary' => mb_substr($line, 0, 220),
                        'body'    => $line . "\n",
                    ];
                } else {
                    $cur['body'] .= $line . "\n";
                }
            }
        }

        $flush();

        if (!$entries) {
            foreach ($lines as $line) {
                if ($line === '') continue;
                $entries[] = ['ts'=>'','level'=>'info','summary'=>mb_substr($line,0,220),'body'=>$line];
            }
        }

        return $entries;
    }

    /** @param list<array{ts:string,level:string,summary:string,body:string}> $entries */
    public function counts(array $entries): array
    {
        $counts = ['debug' => 0, 'info' => 0, 'warn' => 0, 'error' => 0];
        foreach ($entries as $e) {
            $l = (string)($e['level'] ?? 'info');
            $l = strtolower($l);
            if ($l === 'warning') $l = 'warn';
            if (!isset($counts[$l])) $l = 'info';
            $counts[$l]++;
        }
        return $counts;
    }
}
