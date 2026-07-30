<?php

declare(strict_types=1);

return [
    'env' => getenv('APP_ENV') ?: 'dev',
    'base_url' => getenv('APP_BASE_URL') ?: 'https://www.hm491715.webhm.pro',
    'jwt_issuer' => getenv('JWT_ISSUER') ?: 'secure-p2p-backend',
    'jwt_secret' => getenv('JWT_SECRET') ?: 'change-this-in-production',
    'access_ttl_seconds' => 600,
    'license_ttl_seconds' => 600,
    'refresh_ttl_seconds' => 60 * 60 * 24 * 30,
];
