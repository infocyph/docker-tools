<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class TailReader
{
    public function isGz(string $file): bool
    {
        return str_ends_with(strtolower($file), '.gz');
    }

    /** @return array{0:int,1:string,2:string} */
    public function tailText(string $file, int $lines): array
    {
        $lines = max(10, $lines);

        if ($this->isGz($file)) {
            $h = @gzopen($file, 'rb');
            if (!$h) return [1, '', 'gzopen failed'];

            $content = '';
            while (!gzeof($h)) {
                $content .= (string)gzread($h, 8192);
                if (strlen($content) > 32_000_000) break;
            }
            gzclose($h);

            $all = preg_split("/\r\n|\n|\r/", $content) ?: [];
            $slice = array_slice($all, -$lines);

            return [0, implode("\n", $slice), ''];
        }

        return $this->tailPlainPhp($file, $lines);
    }

    /** @return array{0:int,1:string,2:string} */
    private function tailPlainPhp(string $file, int $lines): array
    {
        $fp = @fopen($file, 'rb');
        if (!$fp) return [1, '', 'fopen failed'];

        if (fseek($fp, 0, SEEK_END) !== 0) { fclose($fp); return [1, '', 'fseek failed']; }

        $pos = ftell($fp);
        if ($pos === false) { fclose($fp); return [1, '', 'ftell failed']; }

        $buf = '';
        $chunk = 8192;

        while ($pos > 0 && substr_count($buf, "\n") < ($lines + 1)) {
            $read = ($pos >= $chunk) ? $chunk : $pos;
            $pos -= $read;

            if (fseek($fp, $pos, SEEK_SET) !== 0) break;

            $data = fread($fp, $read);
            if ($data === false || $data === '') break;

            $buf = $data . $buf;

            if (strlen($buf) > 8_000_000) break;
        }

        fclose($fp);

        $all = preg_split("/\r\n|\n|\r/", $buf) ?: [];
        $slice = array_slice($all, -$lines);

        return [0, implode("\n", $slice), ''];
    }
}
