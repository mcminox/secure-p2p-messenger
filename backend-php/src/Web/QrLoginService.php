<?php

declare(strict_types=1);

namespace SecureP2P\Web;

use SecureP2P\Infra\Db;

final class QrLoginService
{
    public function __construct(private readonly Db $db) {}

    public function createChallenge(): array
    {
        $id = bin2hex(random_bytes(16));
        $payload = bin2hex(random_bytes(32));
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO web_qr_challenges (challenge_id, payload, status, expires_at, created_at)
             VALUES (:id, :payload, :status, DATE_ADD(NOW(), INTERVAL 2 MINUTE), NOW())'
        );
        $stmt->execute(['id' => $id, 'payload' => $payload, 'status' => 'pending']);
        return [
            'challenge_id' => $id,
            'challenge_payload' => $payload,
            'qr_payload' => 'spm://web-login?challenge=' . $id . '&payload=' . $payload,
        ];
    }

    public function approve(string $challengeId, string $userId, string $deviceSignature): array
    {
        $code = bin2hex(random_bytes(24));
        $stmt = $this->db->pdo()->prepare(
            'UPDATE web_qr_challenges
             SET status = :status, approved_user_id = :uid, device_signature = :sig, session_code = :code, approved_at = NOW()
             WHERE challenge_id = :id AND status = :pending'
        );
        $stmt->execute([
            'status' => 'approved',
            'uid' => $userId,
            'sig' => $deviceSignature,
            'code' => $code,
            'id' => $challengeId,
            'pending' => 'pending',
        ]);
        return ['approved' => $stmt->rowCount() > 0, 'web_session_code' => $code];
    }

    public function poll(string $challengeId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT status, session_code FROM web_qr_challenges WHERE challenge_id = :id'
        );
        $stmt->execute(['id' => $challengeId]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['status' => 'not_found'];
        }
        return ['status' => (string)$row['status'], 'web_session_code' => $row['session_code']];
    }

    public function exchangeSession(string $sessionCode): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT approved_user_id FROM web_qr_challenges WHERE session_code = :code AND status = :status'
        );
        $stmt->execute(['code' => $sessionCode, 'status' => 'approved']);
        $row = $stmt->fetch();
        if (!$row) {
            return ['ok' => false, 'error' => 'invalid_session_code'];
        }
        return [
            'ok' => true,
            'session_token' => bin2hex(random_bytes(32)),
            'user_id' => (string)$row['approved_user_id'],
        ];
    }
}
