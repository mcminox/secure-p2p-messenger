<?php

declare(strict_types=1);

namespace SecureP2P\Risk;

use SecureP2P\Infra\Db;

final class RiskService
{
    public function __construct(private readonly Db $db) {}

    public function report(string $userId, string $deviceId, string $event, array $payload): array
    {
        $score = $this->scoreEvent($event, $payload);
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO risk_events (user_id, device_id, event, payload_json, score, created_at)
             VALUES (:uid, :did, :event, :payload, :score, NOW())'
        );
        $stmt->execute([
            'uid' => $userId,
            'did' => $deviceId,
            'event' => $event,
            'payload' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            'score' => $score,
        ]);
        return [
            'accepted' => true,
            'risk_score' => $score,
            'required_action' => $score >= 70 ? 'step_up_required' : 'allow',
        ];
    }

    private function scoreEvent(string $event, array $payload): int
    {
        $high = ['frida_detected', 'xposed_detected', 'license_replay', 'hook_framework_detected'];
        $medium = ['root_detected', 'emulator_detected', 'debugger_attached'];
        if (in_array($event, $high, true)) {
            return 90;
        }
        if (in_array($event, $medium, true)) {
            return 60;
        }
        if (($payload['suspicious'] ?? false) === true) {
            return 50;
        }
        return 10;
    }
}
