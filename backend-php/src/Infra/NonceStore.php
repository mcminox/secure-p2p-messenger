<?php

declare(strict_types=1);

namespace SecureP2P\Infra;

final class NonceStore
{
    private string $path;

    public function __construct(?string $path = null)
    {
        $this->path = $path ?? sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'spm_nonce_store.json';
    }

    public function remember(string $deviceId, string $nonce): bool
    {
        $all = $this->read();
        $key = $deviceId . ':' . $nonce;
        if (isset($all[$key])) {
            return false;
        }
        $all[$key] = time();
        $this->write($all);
        return true;
    }

    private function read(): array
    {
        if (!is_file($this->path)) {
            return [];
        }
        $raw = file_get_contents($this->path);
        if (!is_string($raw) || $raw === '') {
            return [];
        }
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }

    private function write(array $all): void
    {
        file_put_contents($this->path, json_encode($all));
    }
}
