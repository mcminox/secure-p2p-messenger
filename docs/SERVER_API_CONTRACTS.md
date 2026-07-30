# Secure P2P Server API Contracts

This document defines the backend contracts for auth, billing, licensing and risk.

## Security principles

- All endpoints require TLS 1.2+.
- Requests use `X-Request-Id` and `X-Timestamp`.
- Mutating endpoints require `Idempotency-Key`.
- Access tokens are short-lived JWT (10 minutes).
- Refresh tokens are opaque, rotating, server-stored.
- Device-bound license TTL is 5-15 minutes.

## Auth

### POST `/v1/auth/register`
- Body: `email`, `password_hash`, `device_id`, `device_pubkey`, `app_build_fingerprint`
- Returns: `user_id`, `access_token`, `refresh_token`, `mfa_required`

### POST `/v1/auth/login`
- Body: `email`, `password_hash`, `device_id`, `device_pubkey`, `device_attestation`, `app_build_fingerprint`
- Returns: `access_token`, `refresh_token`, `mfa_required`, `risk_flags[]`

### POST `/v1/auth/refresh`
- Body: `refresh_token`, `device_id`
- Returns: `access_token`, `refresh_token`

### POST `/v1/auth/logout`
- Body: `refresh_token`
- Returns: `ok`

### POST `/v1/auth/mfa/verify`
- Body: `code`, `device_id`
- Returns: `access_token`, `refresh_token`

## Device ownership

### POST `/v1/devices/bind`
- Auth: access token
- Body: `device_id`, `device_pubkey`, `app_build_fingerprint`
- Returns: `bound`, `requires_owner_approval`

### POST `/v1/devices/approve`
- Auth: access token + step-up verification
- Body: `device_id`, `challenge_signature`
- Returns: `approved`

## Billing

### GET `/v1/billing/providers`
- Returns enabled providers and currencies.

### POST `/v1/billing/checkout`
- Auth: access token
- Body: `provider`, `plan_id`, `currency`, `return_url`, `cancel_url`
- Returns: `checkout_url`, `payment_id`, `expires_at`

### GET `/v1/billing/subscription`
- Auth: access token
- Returns: `status`, `plan_id`, `period_end`, `grace_until`, `renewal_provider`

### POST `/v1/billing/webhook/{provider}`
- Verifies provider signature.
- Idempotent by event ID.
- Updates subscription state machine.

### Subscription states
- `trial`
- `active`
- `past_due`
- `grace`
- `expired`
- `blocked`

## Licensing

### POST `/v1/license/issue`
- Auth: access token
- Body: `device_id`, `device_pubkey`, `app_build_fingerprint`, `nonce`
- Returns:
  - `license_token` (signed JWT)
  - `server_nonce`
  - `expires_at`

### POST `/v1/license/verify`
- Auth: access token
- Body: `license_token`, `nonce`, `proof`
- Returns: `valid`, `risk_score`, `action`

### POST `/v1/license/revoke`
- Auth: owner/admin + step-up auth
- Body: `device_id`, `reason`
- Returns: `revoked`

## Login on website via app (QR flow)

### POST `/v1/web/qr/challenge`
- Returns: `challenge_id`, `challenge_payload`, `qr_payload`, `expires_at`

### POST `/v1/web/qr/approve`
- Auth: app access token
- Body: `challenge_id`, `device_signature`
- Returns: `approved`, `web_session_code`

### POST `/v1/web/qr/poll`
- Body: `challenge_id`
- Returns pending/approved/rejected; on approved returns one-time `web_session_code`.

### POST `/v1/web/session/exchange`
- Body: `web_session_code`
- Returns: web `session_token`.

## RTC matchmaking/signaling (token-based, no direct IP lookup)

### POST `/v1/rtc/ice`
- Body: `user_id`, `active_subscription`
- Returns dynamic `ice_servers` (STUN/TURN) and queue class.

### POST `/v1/rtc/open`
- Body: `user_id`, `nickname`, `connect_token`, `device_id`, `offer_sdp`, `active_subscription`
- Returns: `session_id`, `secret`, `expires_in_sec`.

### POST `/v1/rtc/find`
- Body: `requester_user_id`, `target_connect_token`
- Returns: `session_id`, `secret`, `peer_nickname`, `offer_sdp`.
- Search order uses subscription priority (active users first).

### POST `/v1/rtc/answer`
- Body: `session_id`, `secret`, `answer_sdp`
- Saves callee answer for initiator.

### POST `/v1/rtc/poll`
- Body: `session_id`, `secret`
- Returns answer status; after successful handshake server removes session data.

## Risk events

### POST `/v1/risk/report`
- Auth: access token
- Body: `device_id`, `event`, `payload`, `local_time`, `app_build_fingerprint`
- Returns: `accepted`, `risk_score`, `required_action`

### High-risk enforcement
- Server can force `step_up_required`.
- Server can force `license_denied`.
- Server can force `session_terminate`.

## Subscription-gated features

- Group chat creation and maintenance.
- Priority matchmaking queue in RTC search.
- Extended media size limits.
- Advanced security journal features.

## License JWT claims

- `iss`: backend issuer
- `sub`: user id
- `did`: device id
- `dpk`: device public key hash
- `abf`: app build fingerprint
- `sub_state`: subscription state
- `scp`: permissions list (`chat:send`, `chat:receive`, `sync:pull`)
- `jti`: token id
- `iat`, `exp`, `nbf`
- `nonce_ctr`: monotonic counter

## Anti-replay

- Every critical request includes `nonce`.
- Server stores nonce window per device.
- Duplicate or stale nonce -> reject and risk increment.
