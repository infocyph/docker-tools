<?php
declare(strict_types=1);

namespace LogViewer\Services;

final class GrepRunner
{
    public function __construct(
        private readonly ShellRunner $sh,
        private readonly TailReader $tail,
    ) {}

    /** @return array{0:int,1:string,2:string} */
    public function grep(string $file, string $q, int $limit = 500): array
    {
        $q = trim($q);
        if ($q === '') return [0, '', 'missing q'];

        $limit = max(50, min(5000, $limit));
        $rg = 'rg --no-heading --line-number --max-count ' . (int)$limit . ' -S -- ' . escapeshellarg($q);

        if ($this->tail->isGz($file)) {
            $cmd = 'gzip -dc -- ' . escapeshellarg($file) . ' | ' . $rg;
            return $this->sh->sh($cmd, 15);
        }

        return $this->sh->sh($rg . ' ' . escapeshellarg($file), 12);
    }
}
