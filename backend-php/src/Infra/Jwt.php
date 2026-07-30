<?php

declare(strict_types=1);

namespace SecureP2P\Infra;

final class Jwt
{
    public static function issue(array $claims, string $secret): string
    {
        $header = ['alg' => 'HS256', 'typ' => 'JWT'];
        $segments = [
            self::b64(json_encode($header, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)),
            self::b64(json_encode($claims, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)),
        ];
        $sig = hash_hmac('sha256', implode('.', $segments), $secret, true);
        $segments[] = self::b64($sig);
        return implode('.', $segments);
    }

    public static function verify(string $token, string $secret): ?array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            return null;
        }
        [$h, $p, $s] = $parts;
        $expected = self::b64(hash_hmac('sha256', $h . '.' . $p, $secret, true));
        if (!hash_equals($expected, $s)) {
            return null;
        }
        $claimsRaw = base64_decode(strtr($p, '-_', '+/'), true);
        if (!is_string($claimsRaw)) {
            return null;
        }
        $claims = json_decode($claimsRaw, true);
        if (!is_array($claims)) {
            return null;
        }
        if (isset($claims['exp']) && time() >= (int)$claims['exp']) {
            return null;
        }
        return $claims;
    }

    private static function b64(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }
}
