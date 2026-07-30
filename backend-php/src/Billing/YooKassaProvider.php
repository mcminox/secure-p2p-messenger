<?php

declare(strict_types=1);

namespace SecureP2P\Billing;

final class YooKassaProvider implements PaymentProvider
{
    public function code(): string
    {
        return 'yookassa';
    }

    public function createCheckout(array $payload): array
    {
        $paymentId = 'yk_' . bin2hex(random_bytes(8));
        return [
            'provider' => $this->code(),
            'payment_id' => $paymentId,
            'checkout_url' => 'https://yookassa.ru/checkout/' . $paymentId,
        ];
    }

    public function validateWebhook(string $body, array $headers): bool
    {
        $secret = getenv('YOOKASSA_WEBHOOK_SECRET') ?: '';
        if ($secret === '') {
            return false;
        }
        $sig = (string)($headers['x-yookassa-signature'] ?? '');
        if ($sig === '') {
            return false;
        }
        $expected = hash_hmac('sha256', $body, $secret);
        return hash_equals($expected, $sig);
    }

    public function normalizeWebhookEvent(array $payload): array
    {
        return [
            'event_id' => (string)($payload['event'] ?? ('yk_evt_' . bin2hex(random_bytes(6)))),
            'status' => (string)($payload['object']['status'] ?? 'pending'),
            'payment_id' => (string)($payload['object']['id'] ?? ''),
            'user_id' => (string)($payload['object']['metadata']['user_id'] ?? ''),
        ];
    }
}
