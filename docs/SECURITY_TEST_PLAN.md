# Security Validation Checklist

## Pentest checklist

- Try using expired `license_token` -> must be denied.
- Try replaying same nonce for `/v1/license/issue` -> must raise risk event.
- Try forged webhook signature for Stripe/YooKassa -> must be rejected.
- Try duplicate webhook event ID -> must be idempotent and not double-activate subscription.
- Try login from unapproved device -> must require owner approval.
- Try bypass with rooted/debugged device -> app should report risk and fail closed.

## Billing anti-fraud scenarios

- Payment success webhook activates `subscriptions.status=active`.
- Payment failure moves state to `past_due` then `grace` then `expired`.
- Manual local client state changes do not affect subscription on server.
- Server-side cancellation immediately blocks new license issuance.

## Web QR auth scenarios

- Challenge expires in 2 minutes.
- Approval generates one-time `web_session_code`.
- Polling returns approved only once session code is created.
- Session exchange fails on reused/invalid code.

## Release validation

- Verify release build has `minifyEnabled` and `shrinkResources`.
- Verify `FLAG_SECURE` blocks screenshots.
- Verify `usesCleartextTraffic=false`.
- Verify critical secure flows blocked without server license.
