<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class ShellRunner
{
    /** @return array{0:int,1:string,2:string} */
    public function run(array $cmd, int $timeout = 8): array
    {
        $des = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
        $p = @proc_open($cmd, $des, $pipes, null, null);
        if (!is_resource($p)) return [1, '', 'proc_open failed'];

        stream_set_blocking($pipes[1], true);
        stream_set_blocking($pipes[2], true);

        $start = time();
        while (true) {
            $st = proc_get_status($p);
            if (!$st['running']) break;
            if ((time() - $start) > $timeout) {
                @proc_terminate($p);
                break;
            }
            usleep(50_000);
        }

        $out = stream_get_contents($pipes[1]) ?: '';
        $err = stream_get_contents($pipes[2]) ?: '';
        fclose($pipes[1]);
        fclose($pipes[2]);

        $code = proc_close($p);
        return [$code, $out, $err];
    }

    /** @return array{0:int,1:string,2:string} */
    public function sh(string $cmd, int $timeout = 10): array
    {
        return $this->run(['/bin/sh', '-lc', $cmd], $timeout);
    }
}
