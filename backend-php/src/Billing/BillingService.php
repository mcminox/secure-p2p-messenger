<?php

declare(strict_types=1);

namespace SecureP2P\Billing;

use SecureP2P\Infra\Db;

final class BillingService
{
    private array $providers = [];

    public function __construct(private readonly Db $db, PaymentProvider ...$providers)
    {
        foreach ($providers as $provider) {
            $this->providers[$provider->code()] = $provider;
        }
    }

    public function providers(): array
    {
        return array_keys($this->providers);
    }

    public function checkout(string $provider, string $userId, string $planId, string $currency): array
    {
        $p = $this->providers[$provider] ?? null;
        if ($p === null) {
            return ['ok' => false, 'error' => 'unknown_provider'];
        }
        $checkout = $p->createCheckout(compact('userId', 'planId', 'currency'));
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO payments (payment_id, user_id, provider, plan_id, currency, status, created_at)
             VALUES (:pid, :uid, :provider, :plan, :currency, :status, NOW())'
        );
        $stmt->execute([
            'pid' => $checkout['payment_id'],
            'uid' => $userId,
            'provider' => $provider,
            'plan' => $planId,
            'currency' => $currency,
            'status' => 'pending',
        ]);
        return ['ok' => true] + $checkout;
    }

    public function processWebhook(string $provider, string $body, array $headers, array $payload): array
    {
        $p = $this->providers[$provider] ?? null;
        if ($p === null) {
            return ['ok' => false, 'error' => 'unknown_provider'];
        }
        if (!$p->validateWebhook($body, $headers)) {
            return ['ok' => false, 'error' => 'invalid_signature'];
        }
        $event = $p->normalizeWebhookEvent($payload);
        $pdo = $this->db->pdo();

        $exists = $pdo->prepare('SELECT id FROM webhook_events WHERE event_id = :eid');
        $exists->execute(['eid' => $event['event_id']]);
        if ($exists->fetch()) {
            return ['ok' => true, 'idempotent' => true];
        }

        $insEvt = $pdo->prepare(
            'INSERT INTO webhook_events (event_id, provider, payload_json, created_at)
             VALUES (:eid, :provider, :payload, NOW())'
        );
        $insEvt->execute([
            'eid' => $event['event_id'],
            'provider' => $provider,
            'payload' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        ]);

        $upd = $pdo->prepare('UPDATE payments SET status = :status, updated_at = NOW() WHERE payment_id = :pid');
        $upd->execute(['status' => $event['status'], 'pid' => $event['payment_id']]);

        if ($event['status'] === 'succeeded' || $event['status'] === 'paid') {
            $this->activateSubscription((string)$event['user_id']);
        }

        return ['ok' => true, 'processed' => true];
    }

    public function activateSubscription(string $userId): void
    {
        if ($userId === '') {
            return;
        }
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO subscriptions (user_id, status, plan_id, period_end, created_at, updated_at)
             VALUES (:uid, :status, :plan, DATE_ADD(NOW(), INTERVAL 30 DAY), NOW(), NOW())
             ON DUPLICATE KEY UPDATE
                status = VALUES(status),
                period_end = VALUES(period_end),
                updated_at = NOW()'
        );
        $stmt->execute(['uid' => $userId, 'status' => 'active', 'plan' => 'pro-monthly']);
    }

    public function subscriptionOf(string $userId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT status, plan_id, period_end, grace_until FROM subscriptions WHERE user_id = :uid'
        );
        $stmt->execute(['uid' => $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return [
                'status' => 'trial',
                'plan_id' => 'free',
                'features' => $this->featuresForStatus('trial'),
            ];
        }
        $status = (string)$row['status'];
        return [
            'status' => $status,
            'plan_id' => (string)$row['plan_id'],
            'period_end' => (string)$row['period_end'],
            'grace_until' => (string)($row['grace_until'] ?? ''),
            'features' => $this->featuresForStatus($status),
        ];
    }

    public function grantSubscriptionAdmin(string $userId, string $planId, string $reason): array
    {
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO subscriptions (user_id, status, plan_id, period_end, created_at, updated_at)
             VALUES (:uid, :status, :plan, DATE_ADD(NOW(), INTERVAL 30 DAY), NOW(), NOW())
             ON DUPLICATE KEY UPDATE
                status = VALUES(status),
                plan_id = VALUES(plan_id),
                period_end = VALUES(period_end),
                updated_at = NOW()'
        );
        $stmt->execute(['uid' => $userId, 'status' => 'active', 'plan' => $planId]);
        $audit = $this->db->pdo()->prepare(
            'INSERT INTO admin_audit_log (admin_actor, action, target_user_id, payload_json, created_at)
             VALUES (:actor, :action, :uid, :payload, NOW())'
        );
        $audit->execute([
            'actor' => getenv('ADMIN_ACTOR') ?: 'manual_admin',
            'action' => 'grant_subscription',
            'uid' => $userId,
            'payload' => json_encode(['plan_id' => $planId, 'reason' => $reason], JSON_UNESCAPED_UNICODE),
        ]);
        return ['ok' => true, 'reason' => $reason];
    }

    private function featuresForStatus(string $status): array
    {
        $active = in_array($status, ['active', 'grace'], true);
        return [
            'group_chats' => $active,
            'priority_matchmaking_queue' => $active,
            'extended_media_limit_mb' => $active ? 256 : 32,
            'secure_cloud_backup_beta' => $active,
            'advanced_security_journal' => $active,
            'faster_signaling' => $active,
            'premium_badge' => $active,
        ];
    }
}
