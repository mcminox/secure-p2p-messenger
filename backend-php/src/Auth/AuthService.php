<?php

declare(strict_types=1);

namespace SecureP2P\Auth;

use SecureP2P\Infra\Db;
use SecureP2P\Infra\Jwt;

final class AuthService
{
    public function __construct(
        private readonly Db $db,
        private readonly array $cfg,
    ) {}

    public function login(string $email, string $passwordHash, string $deviceId): array
    {
        $pdo = $this->db->pdo();
        $stmt = $pdo->prepare(
            'SELECT id, password_hash, is_mfa_enabled, nickname, connect_token FROM users WHERE email = :email'
        );
        $stmt->execute(['email' => $email]);
        $u = $stmt->fetch();
        if (!$u || !hash_equals((string)$u['password_hash'], $passwordHash)) {
            return ['ok' => false, 'error' => 'invalid_credentials'];
        }

        $now = time();
        $access = Jwt::issue([
            'iss' => $this->cfg['jwt_issuer'],
            'sub' => (string)$u['id'],
            'did' => $deviceId,
            'iat' => $now,
            'exp' => $now + (int)$this->cfg['access_ttl_seconds'],
        ], $this->cfg['jwt_secret']);

        $refresh = bin2hex(random_bytes(32));
        $exp = $now + (int)$this->cfg['refresh_ttl_seconds'];
        $insert = $pdo->prepare(
            'INSERT INTO refresh_tokens (token, user_id, device_id, expires_at, created_at)
             VALUES (:t, :u, :d, FROM_UNIXTIME(:e), NOW())'
        );
        $insert->execute(['t' => $refresh, 'u' => $u['id'], 'd' => $deviceId, 'e' => $exp]);

        return [
            'ok' => true,
            'user_id' => (string)$u['id'],
            'access_token' => $access,
            'refresh_token' => $refresh,
            'mfa_required' => (bool)$u['is_mfa_enabled'],
            'nickname' => (string)($u['nickname'] ?? ''),
            'connect_token' => (string)($u['connect_token'] ?? ''),
        ];
    }

    public function register(
        string $email,
        string $passwordHash,
        string $deviceId,
        string $nickname,
    ): array
    {
        $pdo = $this->db->pdo();
        $token = $this->generateConnectToken();
        $stmt = $pdo->prepare(
            'INSERT INTO users (email, password_hash, nickname, connect_token, created_at)
             VALUES (:email, :ph, :nick, :token, NOW())'
        );
        $stmt->execute(['email' => $email, 'ph' => $passwordHash, 'nick' => $nickname, 'token' => $token]);
        $id = (string)$pdo->lastInsertId();
        $bind = $pdo->prepare(
            'INSERT INTO devices (user_id, device_id, is_owner_device, approved, created_at)
             VALUES (:uid, :did, TRUE, TRUE, NOW())'
        );
        $bind->execute(['uid' => $id, 'did' => $deviceId]);
        $res = $this->login($email, $passwordHash, $deviceId);
        if ($res['ok']) {
            $res['nickname'] = $nickname;
            $res['connect_token'] = $token;
        }
        return $res;
    }

    public function verifyMfa(string $userId, string $code): array
    {
        $stmt = $this->db->pdo()->prepare('SELECT totp_secret FROM users WHERE id = :id');
        $stmt->execute(['id' => $userId]);
        $u = $stmt->fetch();
        if (!$u) {
            return ['ok' => false, 'error' => 'user_not_found'];
        }
        $secret = (string)($u['totp_secret'] ?? '');
        if ($secret === '' || !hash_equals(substr(hash('sha256', $secret . date('YmdHi')), 0, 6), $code)) {
            return ['ok' => false, 'error' => 'mfa_invalid'];
        }
        return ['ok' => true];
    }

    public function bindDevice(string $userId, string $deviceId, string $devicePubkey): array
    {
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO devices (user_id, device_id, device_pubkey, is_owner_device, approved, created_at)
             VALUES (:uid, :did, :pk, FALSE, FALSE, NOW())
             ON DUPLICATE KEY UPDATE device_pubkey = VALUES(device_pubkey)'
        );
        $stmt->execute(['uid' => $userId, 'did' => $deviceId, 'pk' => $devicePubkey]);
        return ['bound' => true, 'requires_owner_approval' => true];
    }

    public function approveDevice(string $userId, string $deviceId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE devices SET approved = TRUE, approved_at = NOW()
             WHERE user_id = :uid AND device_id = :did'
        );
        $stmt->execute(['uid' => $userId, 'did' => $deviceId]);
        return ['approved' => $stmt->rowCount() > 0];
    }

    public function profile(string $userId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT nickname, connect_token FROM users WHERE id = :id'
        );
        $stmt->execute(['id' => $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['ok' => false, 'error' => 'not_found'];
        }
        return [
            'ok' => true,
            'nickname' => (string)$row['nickname'],
            'connect_token' => (string)$row['connect_token'],
        ];
    }

    private function generateConnectToken(): string
    {
        return strtoupper(substr(bin2hex(random_bytes(12)), 0, 20));
    }
}
