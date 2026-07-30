<?php

declare(strict_types=1);

namespace SecureP2P\Web;

use SecureP2P\Infra\Db;

final class RtcSignalingService
{
    public function __construct(private readonly Db $db) {}

    public function iceConfig(string $userId, bool $activeSubscription): array
    {
        $servers = [
            ['urls' => ['stun:stun.l.google.com:19302']],
            ['urls' => ['stun:stun1.l.google.com:19302']],
        ];
        $turnEnabled = (getenv('TURN_ENABLED') ?: '0') === '1';
        $turnHost = getenv('TURN_HOST') ?: '';
        if ($turnEnabled && $turnHost !== '') {
            $username = 'u' . $userId . '-' . time();
            $credential = hash('sha256', $username . '::' . (getenv('TURN_SECRET') ?: 'turn-secret'));
            $servers[] = [
                'urls' => [
                    'turn:' . $turnHost . ':3478?transport=udp',
                    'turns:' . $turnHost . ':5349?transport=tcp',
                ],
                'username' => $username,
                'credential' => $credential,
            ];
        }
        return [
            'ice_servers' => $servers,
            'priority' => $activeSubscription ? 'fast_lane' : 'standard',
            'relay' => $turnEnabled && $turnHost !== '' ? 'enabled' : 'disabled',
        ];
    }

    public function openPresence(
        string $userId,
        string $nickname,
        string $connectToken,
        string $deviceId,
        string $offerSdp,
        bool $activeSubscription,
    ): array {
        $this->cleanupExpired();
        $sessionId = bin2hex(random_bytes(12));
        $secret = bin2hex(random_bytes(24));
        $priority = $activeSubscription ? 0 : 100;
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO rtc_sessions
             (session_id, secret, owner_user_id, owner_nickname, owner_connect_token, owner_device_id, offer_sdp, priority, status, expires_at, created_at, updated_at)
             VALUES (:sid, :secret, :uid, :nick, :token, :did, :offer, :priority, :status, DATE_ADD(NOW(), INTERVAL 90 SECOND), NOW(), NOW())'
        );
        $stmt->execute([
            'sid' => $sessionId,
            'secret' => $secret,
            'uid' => $userId,
            'nick' => $nickname,
            'token' => $connectToken,
            'did' => $deviceId,
            'offer' => $offerSdp,
            'priority' => $priority,
            'status' => 'waiting',
        ]);
        return ['session_id' => $sessionId, 'secret' => $secret, 'expires_in_sec' => 90];
    }

    public function findByToken(string $requesterUserId, string $targetToken): array
    {
        $this->cleanupExpired();
        $stmt = $this->db->pdo()->prepare(
            'SELECT session_id, secret, owner_nickname, offer_sdp
             FROM rtc_sessions
             WHERE owner_connect_token = :token
               AND CAST(owner_user_id AS CHAR) <> :uid
               AND status = :status
               AND expires_at > NOW()
             ORDER BY priority ASC, created_at ASC
             LIMIT 1'
        );
        $stmt->execute([
            'token' => $targetToken,
            'uid' => $requesterUserId,
            'status' => 'waiting',
        ]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['ok' => false, 'error' => 'not_found'];
        }
        return [
            'ok' => true,
            'session_id' => (string)$row['session_id'],
            'secret' => (string)$row['secret'],
            'peer_nickname' => (string)$row['owner_nickname'],
            'offer_sdp' => (string)$row['offer_sdp'],
        ];
    }

    public function submitAnswer(string $sessionId, string $secret, string $answerSdp): array
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE rtc_sessions
             SET answer_sdp = :answer, status = :status, updated_at = NOW()
             WHERE session_id = :sid AND secret = :secret AND status = :waiting'
        );
        $stmt->execute([
            'answer' => $answerSdp,
            'status' => 'answered',
            'sid' => $sessionId,
            'secret' => $secret,
            'waiting' => 'waiting',
        ]);
        return ['ok' => $stmt->rowCount() > 0];
    }

    public function pollAnswer(string $sessionId, string $secret): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT answer_sdp, status FROM rtc_sessions WHERE session_id = :sid AND secret = :secret'
        );
        $stmt->execute(['sid' => $sessionId, 'secret' => $secret]);
        $row = $stmt->fetch();
        if (!$row) {
            return ['ok' => false, 'error' => 'not_found'];
        }
        if ((string)$row['status'] !== 'answered' || empty($row['answer_sdp'])) {
            return ['ok' => true, 'status' => (string)$row['status']];
        }
        $del = $this->db->pdo()->prepare('DELETE FROM rtc_sessions WHERE session_id = :sid');
        $del->execute(['sid' => $sessionId]);
        return ['ok' => true, 'status' => 'connected', 'answer_sdp' => (string)$row['answer_sdp']];
    }

    private function cleanupExpired(): void
    {
        $stmt = $this->db->pdo()->prepare('DELETE FROM rtc_sessions WHERE expires_at <= NOW()');
        $stmt->execute();
    }
}
