# Secure P2P Backend (PHP)

Minimal production-oriented skeleton for auth, billing, licensing, risk and website QR login.

## Run locally

1. Configure env vars:
   - `DB_DSN`
   - `DB_USER`
   - `DB_PASSWORD`
   - `JWT_SECRET`
2. Apply SQL migration from `database/migrations/001_init.sql`.
3. Start server:

```bash
php -S 127.0.0.1:8080 -t public
```

## Deploy on shared hosting (upload folder contents)

If your domain root is e.g. `www/hm491715.webhm.pro`, upload the **contents of this folder** (`backend-php/*`) directly into that root.

Expected in site root after upload:
- `index.php`
- `.htaccess`
- `public/`
- `src/`
- `config/`
- `database/`
- `composer.json`

Health checks:
- `https://your-domain/index.php/v1/health`
- `https://your-domain/index.php?route=/v1/health`

## API endpoints

- `GET /v1/health`
- `POST /v1/auth/login`
- `POST /v1/auth/register` (nickname + connect-token)
- `POST /v1/auth/profile`
- `GET /v1/billing/providers`
- `POST /v1/billing/checkout`
- `POST /v1/billing/subscription`
- `POST /v1/billing/webhook/yookassa`
- `POST /v1/billing/webhook/stripe`
- `POST /v1/admin/subscription/grant` (manual admin approve)
- `POST /v1/license/issue`
- `POST /v1/license/verify`
- `POST /v1/risk/report`
- `POST /v1/web/qr/challenge`
- `POST /v1/web/qr/approve`
- `POST /v1/web/qr/poll`
- `POST /v1/rtc/ice`
- `POST /v1/rtc/open`
- `POST /v1/rtc/find`
- `POST /v1/rtc/answer`
- `POST /v1/rtc/poll`

## Notes

- Webhook processing is idempotent (`webhook_events.event_id`).
- Subscription activation is server-side only.
- License is short-lived and device-bound.
- RTC signaling data is ephemeral and auto-purged after successful handshake or timeout.
- Add real provider signature verification before production launch.

## Domain and TURN

- For your current deployment, set `APP_BASE_URL=https://hm491715.webhm.pro`.
- TURN is optional in this build:
  - `TURN_ENABLED=0` -> STUN-only mode (works on many networks, but not all NAT cases).
  - Later you can enable TURN by setting `TURN_ENABLED=1`, `TURN_HOST`, `TURN_SECRET`.
- Shared-hosting fallback routing:
  - `https://your-domain/index.php/v1/health`
  - or `https://your-domain/index.php?route=/v1/health`

## Temporary open mode (debug only)

- Set `DEV_OPEN_MODE=1` to bypass admin-secret check temporarily (for hosting diagnostics).
- Set back to `DEV_OPEN_MODE=0` after setup.

## Security hardening checklist

- Set strong webhook secrets:
  - `YOOKASSA_WEBHOOK_SECRET`
  - `STRIPE_WEBHOOK_SECRET`
- Set admin secrets:
  - `ADMIN_SECRET`
  - optional audit actor `ADMIN_ACTOR`
- Run DB migration and verify new tables:
  - `rtc_sessions`
  - `admin_audit_log`
