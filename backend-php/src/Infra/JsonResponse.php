<?php

declare(strict_types=1);

namespace SecureP2P\Infra;

final class JsonResponse
{
    public static function ok(array $data, int $status = 200): void
    {
        self::send($data, $status);
    }

    public static function error(string $message, int $status = 400, array $meta = []): void
    {
        self::send(['error' => $message, 'meta' => $meta], $status);
    }

    private static function send(array $data, int $status): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
