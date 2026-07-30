<?php

declare(strict_types=1);

use SecureP2P\Auth\AuthService;
use SecureP2P\Billing\BillingService;
use SecureP2P\Billing\StripeProvider;
use SecureP2P\Billing\YooKassaProvider;
use SecureP2P\Infra\Db;
use SecureP2P\Infra\JsonResponse;
use SecureP2P\Infra\Request;
use SecureP2P\License\LicenseService;
use SecureP2P\Risk\RiskService;
use SecureP2P\Web\QrLoginService;
use SecureP2P\Web\RtcSignalingService;

foreach ([
    __DIR__ . '/../../.env',
    __DIR__ . '/../../env',
    __DIR__ . '/../.env',
    __DIR__ . '/../env',
] as $envPath) {
    if (!is_file($envPath)) {
        continue;
    }
    $lines = @file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) {
        continue;
    }
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $k = trim($k);
        $v = trim($v, " \t\n\r\0\x0B\"'");
        if ($k !== '' && getenv($k) === false) {
            putenv($k . '=' . $v);
            $_ENV[$k] = $v;
            $_SERVER[$k] = $v;
        }
    }
}

if (!empty($_GET['route'])) {
    $_SERVER['REQUEST_URI'] = (string)$_GET['route'];
} elseif (!empty($_SERVER['PATH_INFO'])) {
    $_SERVER['REQUEST_URI'] = (string)$_SERVER['PATH_INFO'];
} elseif (!empty($_SERVER['REQUEST_URI'])) {
    $_SERVER['REQUEST_URI'] = preg_replace('#^/index\.php#', '', (string)$_SERVER['REQUEST_URI']) ?? '/';
}
if (empty($_SERVER['REQUEST_URI'])) {
    $_SERVER['REQUEST_URI'] = '/';
}

$devOpenMode = (getenv('DEV_OPEN_MODE') ?: '1') === '1';

require_once __DIR__ . '/../src/Infra/Request.php';
require_once __DIR__ . '/../src/Infra/JsonResponse.php';
require_once __DIR__ . '/../src/Infra/Db.php';
require_once __DIR__ . '/../src/Infra/Jwt.php';
require_once __DIR__ . '/../src/Auth/AuthService.php';
require_once __DIR__ . '/../src/Billing/PaymentProvider.php';
require_once __DIR__ . '/../src/Billing/YooKassaProvider.php';
require_once __DIR__ . '/../src/Billing/StripeProvider.php';
require_once __DIR__ . '/../src/Billing/BillingService.php';
require_once __DIR__ . '/../src/License/LicenseService.php';
require_once __DIR__ . '/../src/Risk/RiskService.php';
require_once __DIR__ . '/../src/Web/QrLoginService.php';
require_once __DIR__ . '/../src/Web/RtcSignalingService.php';

$appCfg = require __DIR__ . '/../config/app.php';
$dbCfg = require __DIR__ . '/../config/database.php';

$method = Request::method();
$path = Request::path();
$json = Request::json();

if ($method === 'GET' && ($path === '/v1/health' || $path === '/' || $path === '')) {
    $dbReachable = false;
    $dbError = null;
    try {
        $probe = new Db($dbCfg);
        $probe->pdo()->query('SELECT 1');
        $dbReachable = true;
    } catch (\Throwable $e) {
        $dbError = $e->getMessage();
    }
    JsonResponse::ok([
        'ok' => true,
        'service' => 'secure-p2p-backend',
        'db_reachable' => $dbReachable,
        'db_error' => $dbReachable ? null : $dbError,
        'php' => PHP_VERSION,
    ]);
    return;
}

$db = new Db($dbCfg);

$auth = new AuthService($db, $appCfg);
$billing = new BillingService($db, new YooKassaProvider(), new StripeProvider());
$license = new LicenseService($db, $appCfg);
$risk = new RiskService($db);
$qr = new QrLoginService($db);
$rtc = new RtcSignalingService($db);

if ($method === 'POST' && $path === '/v1/auth/login') {
    $email = (string)($json['email'] ?? '');
    $passwordHash = (string)($json['password_hash'] ?? '');
    $deviceId = (string)($json['device_id'] ?? '');
    if ($email === '' || $passwordHash === '' || $deviceId === '') {
        JsonResponse::error('invalid_payload', 422);
        return;
    }
    $res = $auth->login($email, $passwordHash, $deviceId);
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 401);
    return;
}

if ($method === 'POST' && $path === '/v1/auth/register') {
    $email = (string)($json['email'] ?? '');
    $passwordHash = (string)($json['password_hash'] ?? '');
    $deviceId = (string)($json['device_id'] ?? '');
    $nickname = trim((string)($json['nickname'] ?? 'User'));
    if ($email === '' || $passwordHash === '' || $deviceId === '' || $nickname === '') {
        JsonResponse::error('invalid_payload', 422);
        return;
    }
    $res = $auth->register($email, $passwordHash, $deviceId, $nickname);
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 400);
    return;
}

if (($method === 'GET' || $method === 'POST') && $path === '/v1/auth/profile') {
    $uid = (string)($_GET['user_id'] ?? ($json['user_id'] ?? ''));
    $res = $auth->profile($uid);
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 404);
    return;
}

if ($method === 'POST' && $path === '/v1/auth/mfa/verify') {
    $res = $auth->verifyMfa((string)($json['user_id'] ?? ''), (string)($json['code'] ?? ''));
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 401);
    return;
}

if ($method === 'POST' && $path === '/v1/devices/bind') {
    JsonResponse::ok($auth->bindDevice(
        (string)($json['user_id'] ?? ''),
        (string)($json['device_id'] ?? ''),
        (string)($json['device_pubkey'] ?? '')
    ));
    return;
}

if ($method === 'POST' && $path === '/v1/devices/approve') {
    JsonResponse::ok($auth->approveDevice(
        (string)($json['user_id'] ?? ''),
        (string)($json['device_id'] ?? '')
    ));
    return;
}

if ($method === 'GET' && $path === '/v1/billing/providers') {
    JsonResponse::ok(['providers' => $billing->providers()]);
    return;
}

if ($method === 'POST' && $path === '/v1/billing/checkout') {
    $res = $billing->checkout(
        (string)($json['provider'] ?? ''),
        (string)($json['user_id'] ?? ''),
        (string)($json['plan_id'] ?? 'pro-monthly'),
        (string)($json['currency'] ?? 'RUB')
    );
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 400);
    return;
}

if (($method === 'GET' || $method === 'POST') && $path === '/v1/billing/subscription') {
    $uid = (string)($_GET['user_id'] ?? ($json['user_id'] ?? ''));
    JsonResponse::ok($billing->subscriptionOf($uid));
    return;
}

if ($method === 'POST' && $path === '/v1/admin/subscription/grant') {
    if (!$devOpenMode) {
        $adminSecret = Request::header('x-admin-secret') ?? '';
        if (!hash_equals(getenv('ADMIN_SECRET') ?: 'change-admin-secret', $adminSecret)) {
            JsonResponse::error('forbidden', 403);
            return;
        }
    }
    $res = $billing->grantSubscriptionAdmin(
        (string)($json['user_id'] ?? ''),
        (string)($json['plan_id'] ?? 'pro-monthly'),
        (string)($json['reason'] ?? 'manual_approval')
    );
    JsonResponse::ok($res);
    return;
}

if ($method === 'POST' && preg_match('#^/v1/billing/webhook/(yookassa|stripe)$#', $path, $m) === 1) {
    $body = file_get_contents('php://input') ?: '';
    $headers = array_change_key_case(getallheaders(), CASE_LOWER);
    $res = $billing->processWebhook($m[1], $body, $headers, $json);
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 400);
    return;
}

if ($method === 'POST' && $path === '/v1/license/issue') {
    $res = $license->issue(
        (string)($json['user_id'] ?? ''),
        (string)($json['device_id'] ?? ''),
        (string)($json['device_pubkey'] ?? ''),
        (string)($json['app_build_fingerprint'] ?? ''),
        (string)($json['nonce'] ?? '0')
    );
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 403);
    return;
}

if ($method === 'POST' && $path === '/v1/license/verify') {
    $res = $license->verify((string)($json['license_token'] ?? ''));
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error('license_invalid', 403, $res);
    return;
}

if ($method === 'POST' && $path === '/v1/risk/report') {
    $res = $risk->report(
        (string)($json['user_id'] ?? ''),
        (string)($json['device_id'] ?? ''),
        (string)($json['event'] ?? 'unknown'),
        is_array($json['payload'] ?? null) ? $json['payload'] : []
    );
    JsonResponse::ok($res);
    return;
}

if ($method === 'POST' && $path === '/v1/web/qr/challenge') {
    JsonResponse::ok($qr->createChallenge());
    return;
}

if ($method === 'POST' && $path === '/v1/web/qr/approve') {
    JsonResponse::ok($qr->approve(
        (string)($json['challenge_id'] ?? ''),
        (string)($json['user_id'] ?? ''),
        (string)($json['device_signature'] ?? '')
    ));
    return;
}

if ($method === 'POST' && $path === '/v1/web/qr/poll') {
    JsonResponse::ok($qr->poll((string)($json['challenge_id'] ?? '')));
    return;
}

if ($method === 'POST' && $path === '/v1/web/session/exchange') {
    $res = $qr->exchangeSession((string)($json['web_session_code'] ?? ''));
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 400);
    return;
}

if ($method === 'POST' && $path === '/v1/rtc/ice') {
    JsonResponse::ok($rtc->iceConfig(
        (string)($json['user_id'] ?? ''),
        ($json['active_subscription'] ?? false) === true
    ));
    return;
}

if ($method === 'POST' && $path === '/v1/rtc/open') {
    $token = strtoupper(trim((string)($json['connect_token'] ?? '')));
    if ($token === '' || preg_match('/^[A-Z0-9]{8,32}$/', $token) !== 1) {
        JsonResponse::error('invalid_connect_token', 422);
        return;
    }
    JsonResponse::ok($rtc->openPresence(
        (string)($json['user_id'] ?? ''),
        (string)($json['nickname'] ?? 'User'),
        $token,
        (string)($json['device_id'] ?? ''),
        (string)($json['offer_sdp'] ?? ''),
        ($json['active_subscription'] ?? false) === true
    ));
    return;
}

if ($method === 'POST' && $path === '/v1/rtc/find') {
    $targetToken = strtoupper(trim((string)($json['target_connect_token'] ?? '')));
    if ($targetToken === '' || preg_match('/^[A-Z0-9]{8,32}$/', $targetToken) !== 1) {
        JsonResponse::error('invalid_connect_token', 422);
        return;
    }
    $res = $rtc->findByToken(
        (string)($json['requester_user_id'] ?? ''),
        $targetToken
    );
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 404);
    return;
}

if ($method === 'POST' && $path === '/v1/rtc/answer') {
    JsonResponse::ok($rtc->submitAnswer(
        (string)($json['session_id'] ?? ''),
        (string)($json['secret'] ?? ''),
        (string)($json['answer_sdp'] ?? '')
    ));
    return;
}

if ($method === 'POST' && $path === '/v1/rtc/poll') {
    $res = $rtc->pollAnswer(
        (string)($json['session_id'] ?? ''),
        (string)($json['secret'] ?? '')
    );
    $res['ok'] ? JsonResponse::ok($res) : JsonResponse::error((string)$res['error'], 404);
    return;
}

JsonResponse::error('not_found', 404);
