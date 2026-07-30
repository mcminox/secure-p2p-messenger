param(
  [string]$BaseUrl = "https://hm491715.webhm.pro",
  [string]$AdminSecret = "",
  [switch]$WithAdminGrant
)

$ErrorActionPreference = "Stop"

function Step($name) {
  Write-Host ""
  Write-Host "==> $name" -ForegroundColor Cyan
}

function Ok($msg) {
  Write-Host "[OK] $msg" -ForegroundColor Green
}

function Fail($msg) {
  Write-Host "[FAIL] $msg" -ForegroundColor Red
  exit 1
}

function PostJson($url, $body, $headers = @{}) {
  $json = $body | ConvertTo-Json -Depth 20
  return Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType "application/json" -Body $json
}

function GetJson($url, $headers = @{}) {
  return Invoke-RestMethod -Method Get -Uri $url -Headers $headers
}

try {
  $base = $BaseUrl.TrimEnd("/")
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $emailA = "smoke_a_$ts@example.test"
  $emailB = "smoke_b_$ts@example.test"
  $passwordHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  Step "Health"
  $health = GetJson "$base/v1/health"
  if ($health.ok -ne $true) { Fail "Health endpoint returned unexpected payload" }
  Ok "health ok"

  Step "Register user A"
  $regA = PostJson "$base/v1/auth/register" @{
    email = $emailA
    password_hash = $passwordHash
    device_id = "smoke-device-a"
    nickname = "SmokeA"
  }
  if (-not $regA.access_token) { Fail "Register A failed: no access token" }
  if (-not $regA.connect_token) { Fail "Register A failed: no connect token" }
  $userA = [string]$regA.user_id
  $tokenA = [string]$regA.access_token
  $connectTokenA = [string]$regA.connect_token
  Ok "user A registered: $userA"

  Step "Register user B"
  $regB = PostJson "$base/v1/auth/register" @{
    email = $emailB
    password_hash = $passwordHash
    device_id = "smoke-device-b"
    nickname = "SmokeB"
  }
  if (-not $regB.access_token) { Fail "Register B failed: no access token" }
  $userB = [string]$regB.user_id
  $tokenB = [string]$regB.access_token
  Ok "user B registered: $userB"

  Step "Auth login A"
  $loginA = PostJson "$base/v1/auth/login" @{
    email = $emailA
    password_hash = $passwordHash
    device_id = "smoke-device-a"
  }
  if (-not $loginA.access_token) { Fail "Login A failed" }
  Ok "login A ok"

  Step "Profile A"
  $profileA = PostJson "$base/v1/auth/profile?user_id=$userA" @{}
  if (-not $profileA.connect_token) { Fail "Profile A failed: no connect_token" }
  Ok "profile A ok"

  Step "Subscription status A"
  $subA = PostJson "$base/v1/billing/subscription?user_id=$userA" @{}
  if (-not $subA.status) { Fail "Subscription status failed" }
  Ok "subscription status: $($subA.status)"

  Step "Issue/verify license A"
  $licenseIssue = PostJson "$base/v1/license/issue" @{
    user_id = $userA
    device_id = "smoke-device-a"
    device_pubkey = "smoke-device-pubkey-a"
    app_build_fingerprint = "smoke-build"
    nonce = "$ts"
  } @{ Authorization = "Bearer $tokenA" }
  if (-not $licenseIssue.license_token) { Fail "License issue failed" }
  $licenseVerify = PostJson "$base/v1/license/verify" @{
    license_token = [string]$licenseIssue.license_token
    nonce = "$ts"
    proof = "smoke-proof"
  } @{ Authorization = "Bearer $tokenA" }
  if ($licenseVerify.valid -ne $true) { Fail "License verify failed" }
  Ok "license flow ok"

  Step "RTC signaling flow"
  $rtcOpen = PostJson "$base/v1/rtc/open" @{
    user_id = $userA
    nickname = "SmokeA"
    connect_token = $connectTokenA
    device_id = "smoke-device-a"
    offer_sdp = "v=0`r`no=- smoke-offer"
    active_subscription = $false
  } @{ Authorization = "Bearer $tokenA" }
  if (-not $rtcOpen.session_id -or -not $rtcOpen.secret) { Fail "RTC open failed" }

  $rtcFind = PostJson "$base/v1/rtc/find" @{
    requester_user_id = $userB
    target_connect_token = $connectTokenA
  } @{ Authorization = "Bearer $tokenB" }
  if ($rtcFind.ok -ne $true) { Fail "RTC find failed" }

  $answer = "v=0`r`no=- smoke-answer"
  $rtcAnswer = PostJson "$base/v1/rtc/answer" @{
    session_id = [string]$rtcFind.session_id
    secret = [string]$rtcFind.secret
    answer_sdp = $answer
  } @{ Authorization = "Bearer $tokenB" }
  if ($rtcAnswer.ok -ne $true) { Fail "RTC answer failed" }

  $rtcPoll = PostJson "$base/v1/rtc/poll" @{
    session_id = [string]$rtcOpen.session_id
    secret = [string]$rtcOpen.secret
  } @{ Authorization = "Bearer $tokenA" }
  if ($rtcPoll.status -ne "connected") { Fail "RTC poll failed: expected connected" }
  Ok "rtc signaling flow ok"

  Step "Optional admin subscription grant"
  if ($WithAdminGrant) {
    if ([string]::IsNullOrWhiteSpace($AdminSecret)) {
      Fail "WithAdminGrant set but AdminSecret is empty"
    }
    $grant = PostJson "$base/v1/admin/subscription/grant" @{
      user_id = $userA
      plan_id = "pro-monthly"
      reason = "smoke_test"
    } @{ "x-admin-secret" = $AdminSecret }
    if ($grant.ok -ne $true) { Fail "Admin grant failed" }
    Ok "admin grant ok"
  } else {
    Ok "admin grant skipped (pass -WithAdminGrant to test)"
  }

  Write-Host ""
  Write-Host "Smoke test completed successfully." -ForegroundColor Green
}
catch {
  Fail $_.Exception.Message
}
