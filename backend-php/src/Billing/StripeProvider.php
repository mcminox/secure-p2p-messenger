<?php

declare(strict_types=1);

namespace SecureP2P\Billing;

final class StripeProvider implements PaymentProvider
{
    public function code(): string
    {
        return 'stripe';
    }

    public function createCheckout(array $payload): array
    {
        $paymentId = 'st_' . bin2hex(random_bytes(8));
        return [
            'provider' => $this->code(),
            'payment_id' => $paymentId,
            'checkout_url' => 'https://checkout.stripe.com/pay/' . $paymentId,
        ];
    }

    public function validateWebhook(string $body, array $headers): bool
    {
        $secret = getenv('STRIPE_WEBHOOK_SECRET') ?: '';
        if ($secret === '') {
            return false;
        }
        $raw = (string)($headers['stripe-signature'] ?? '');
        if ($raw === '') {
            return false;
        }
        $sig = $raw;
        if (str_starts_with($raw, 'v1=')) {
            $sig = substr($raw, 3);
        }
        $expected = hash_hmac('sha256', $body, $secret);
        return hash_equals($expected, $sig);
    }

    public function normalizeWebhookEvent(array $payload): array
    {
        $obj = $payload['data']['object'] ?? [];
        return [
            'event_id' => (string)($payload['id'] ?? ('st_evt_' . bin2hex(random_bytes(6)))),
            'status' => (string)($obj['status'] ?? 'pending'),
            'payment_id' => (string)($obj['id'] ?? ''),
            'user_id' => (string)($obj['metadata']['user_id'] ?? ''),
        ];
    }
}
