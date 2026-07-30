<?php

declare(strict_types=1);

namespace SecureP2P\Billing;

interface PaymentProvider
{
    public function code(): string;

    public function createCheckout(array $payload): array;

    public function validateWebhook(string $body, array $headers): bool;

    public function normalizeWebhookEvent(array $payload): array;
}
