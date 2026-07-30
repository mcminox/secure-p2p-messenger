<?php

declare(strict_types=1);

namespace SecureP2P\License;

use SecureP2P\Infra\Db;
use SecureP2P\Infra\Jwt;

final class LicenseService
{
    public function __construct(
        private readonly Db $db,
        private readonly array $cfg,
    ) {}

    public function issue(string $userId, string $deviceId, string $devicePubkey, string $buildFp, string $nonce): array
    {
        $sub = $this->subscriptionStatus($userId);
        if (!in_array($sub, ['active', 'trial', 'grace'], true)) {
            return ['ok' => false, 'error' => 'subscription_inactive'];
        }
        $now = time();
        $claims = [
            'iss' => $this->cfg['jwt_issuer'],
            'sub' => $userId,
            'did' => $deviceId,
            'dpk' => hash('sha256', $devicePubkey),
            'abf' => $buildFp,
            'sub_state' => $sub,
            'scp' => ['chat:send', 'chat:receive', 'sync:pull'],
            'nonce_ctr' => $nonce,
            'iat' => $now,
            'exp' => $now + (int)$this->cfg['license_ttl_seconds'],
            'jti' => bin2hex(random_bytes(16)),
        ];

        $token = Jwt::issue($claims, $this->cfg['jwt_secret']);
        $insert = $this->db->pdo()->prepare(
            'INSERT INTO issued_licenses (jti, user_id, device_id, expires_at, created_at)
             VALUES (:jti, :uid, :did, FROM_UNIXTIME(:exp), NOW())'
        );
        $insert->execute([
            'jti' => $claims['jti'],
            'uid' => $userId,
            'did' => $deviceId,
            'exp' => $claims['exp'],
        ]);
        return [
            'ok' => true,
            'license_token' => $token,
            'expires_at' => $claims['exp'],
            'server_nonce' => bin2hex(random_bytes(12)),
        ];
    }

    public function verify(string $token): array
    {
        $claims = Jwt::verify($token, $this->cfg['jwt_secret']);
        if ($claims === null) {
            return ['ok' => false, 'valid' => false, 'action' => 'license_denied'];
        }
        return ['ok' => true, 'valid' => true, 'risk_score' => 0, 'action' => 'allow'];
    }

    private function subscriptionStatus(string $userId): string
    {
        $stmt = $this->db->pdo()->prepare('SELECT status FROM subscriptions WHERE user_id = :uid');
        $stmt->execute(['uid' => $userId]);
        $row = $stmt->fetch();
        return is_array($row) ? (string)$row['status'] : 'trial';
    }
}
