<?php

declare(strict_types=1);

namespace SecureP2P\Infra;

use PDO;

final class Db
{
    private PDO $pdo;

    public function __construct(array $cfg)
    {
        $this->pdo = new PDO(
            $cfg['dsn'],
            $cfg['user'],
            $cfg['password'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]
        );
    }

    public function pdo(): PDO
    {
        return $this->pdo;
    }
}
