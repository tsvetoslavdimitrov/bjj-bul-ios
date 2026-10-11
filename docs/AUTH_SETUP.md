# Auth setup (Supabase dashboard)

The app supports: **email + password** (primary), **Sign in with Apple**, and an **email one-time code** (secondary). Deep links use the URL scheme `bjjbul://login` (declared in `project.yml` → `CFBundleURLTypes`; run `xcodegen` after pulling).

## 1. Email provider
Authentication → **Sign In / Providers** → **Email**:
- **Enable Email provider**: ON
- **Enable email + password sign-in** (allow new users to sign up): ON
- **Confirm email**: turn it **OFF for testing** (sign-up returns a session immediately). For production turn it ON; the app then shows "Check your email to confirm", and the link opens the app via `bjjbul://login`.
- **Minimum password length**: 6 (the app requires ≥ 6).
- **Email OTP length**: 6 (the app accepts 6–10 digits, so 8 also works). **OTP expiry**: 3600 s is fine.

## 2. URL configuration
Authentication → **URL Configuration**:
- **Site URL**: `bjjbul://login` (or your website if you have one; then keep the redirect below).
- **Redirect URLs** → Add: `bjjbul://login` (and optionally `bjjbul://**`).

The app passes `redirectTo: bjjbul://login` for sign-up confirmation, magic links and password reset. `onOpenURL` calls `client.auth.session(from:)`; a recovery link (`type=recovery`) opens the "Set a new password" sheet.

## 3. Email templates
Authentication → **Emails** → Templates. Include both the code and the link:

**Magic Link** (used by "Email me a code"):
```html
<h2>Your BJJ Bul sign-in code</h2>
<p>Enter this code in the app:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>
<p>Or tap to sign in on this phone: <a href="{{ .ConfirmationURL }}">Sign in</a></p>
```
**Confirm signup**:
```html
<h2>Confirm your BJJ Bul account</h2>
<p><a href="{{ .ConfirmationURL }}">Confirm my email</a></p>
<p>Code: {{ .Token }}</p>
```
**Reset Password**:
```html
<h2>Reset your BJJ Bul password</h2>
<p>Open this link on your iPhone: <a href="{{ .ConfirmationURL }}">Set a new password</a></p>
```

## 4. SMTP and rate limits
The built-in mailer is limited (a few emails/hour) and is for testing only → "Too many attempts" errors. For real users set **Custom SMTP** (Authentication → Emails → SMTP, e.g. Resend/Brevo/Postmark) and raise Authentication → **Rate Limits** → emails per hour.

## 5. Sign in with Apple
Unchanged: Providers → Apple → enabled, Client IDs = bundle id `com.bjjbul.app`.

## Troubleshooting
- "Token has expired or is invalid": the code is old (each new request invalidates the previous one), mistyped, or the template doesn't send `{{ .Token }}`. The app strips non-digits, tries type `email` then `magiclink`; request a new code after the 60 s cooldown.
- "Email not confirmed": confirm via the email or disable Confirm email (testing).
- A link opens Safari instead of the app: `bjjbul://login` is missing from Redirect URLs, or the build predates the URL scheme.
