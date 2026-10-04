# Supabase account setup

Venture talks directly to Supabase Auth over HTTPS. The iOS binary contains only
the project URL and publishable anon key. Never add a service-role key to Xcode.

## Create and configure the project

1. Create a Supabase project and keep email/password authentication enabled.
2. In Authentication > Email Templates, change **Confirm signup** to include
   `{{ .Token }}` as a six-digit code.
3. Change **Reset password** to either include `{{ .Token }}` as a six-digit
   code or keep a recovery link that redirects to `venture://auth/reset`.
   The app supports both paths: typed recovery OTP and deep-link recovery.
4. Configure custom SMTP before production so verification delivery is not
   constrained by the development mail service.
5. In Authentication > URL Configuration, set the site URL to `venture://auth`
   and add `venture://auth`, `venture://auth/reset`, and
   `venture://auth/verified` to redirect URLs. The iOS bundle registers the
   `venture` custom URL scheme.
6. Add rate limits, CAPTCHA, and an allowed redirect URL appropriate for the
   production domain.

## Email delivery settings

Supabase's built-in email sender is acceptable only for development. For TestFlight
or App Store builds, turn on **Authentication > Emails > SMTP Settings > Enable
custom SMTP** and use a sender mailbox on a domain you control.

Use these values as the shape of the setup:

```text
sender email address: noreply@yourdomain.com
sender name: Venture
host: smtp.your-provider.com
port: 587
minimum interval per user: 60
username: your SMTP username
password: your SMTP password or app password
```

Prefer port `587` with STARTTLS unless your provider explicitly tells you to use
port `465` with implicit TLS. Do not use port `25`. The sender domain should have
SPF, DKIM, and DMARC configured in DNS or verification/reset messages are more
likely to land in spam.

Provider examples:

```text
Resend:
  sender email address: noreply@your verified domain
  sender name: Venture
  host: smtp.resend.com
  port: 587
  username: resend
  password: your Resend API key

SendGrid:
  sender email address: noreply@your verified domain
  sender name: Venture
  host: smtp.sendgrid.net
  port: 587
  username: apikey
  password: your SendGrid API key

Google Workspace:
  sender email address: noreply@your Google Workspace domain
  sender name: Venture
  host: smtp.gmail.com
  port: 587
  username: full mailbox address
  password: Google app password
```

The current iOS app ships email/password auth only. Phone auth requires an SMS
provider in Supabase, phone-number UI, OTP resend UI, and rate-limit tuning
before it should be enabled.

## Configure the iOS target

Configure both build variants with:

```sh
ruby tools/configure_supabase.rb \
  'https://YOUR_PROJECT.supabase.co' \
  'YOUR_PUBLISHABLE_ANON_KEY'
```

They become `VentureSupabaseURL` and `VentureSupabaseAnonKey` in the generated
Info.plist. The anon key is intentionally publishable and is protected by
Supabase Row Level Security. Do not use the service-role key here.

For command-line builds:

```sh
xcodebuild \
  -project Venture.xcodeproj \
  -scheme Venture \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  VENTURE_SUPABASE_URL='https://YOUR_PROJECT.supabase.co' \
  VENTURE_SUPABASE_ANON_KEY='YOUR_PUBLISHABLE_ANON_KEY' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Deploy account deletion

Run Supabase commands from the repository root. Running them from `~` will fail
with `failed to read supabase/config.toml` or `Entrypoint path does not exist`
because the CLI cannot see the local `supabase/` directory.

```sh
cd /Users/biswajitacharya/Documents/v4
```

Install the Supabase CLI, link the project, then deploy:

```sh
npx supabase login
npx supabase link --project-ref poutjcphymgsfsuklokx
npx supabase functions deploy delete-account --project-ref poutjcphymgsfsuklokx
```

If `supabase link` reports a missing `~/.supabase/profile`, the CLI is not
actually logged in for this shell. Run `supabase login` again, or use
`SUPABASE_ACCESS_TOKEN=... supabase link --project-ref YOUR_PROJECT_REF` from a
token created in the Supabase dashboard.

This repository sets `verify_jwt = true` for `delete-account`. Supabase checks
the caller JWT before invoking the function, and the function then validates the
same caller token before using the server-side service-role key to delete that
authenticated user. The app calls this function before destroying its local
encrypted metrics and keys.

## Deploy database schema

Venture stores account profile metadata, scan sessions, extracted metrics,
measured model outputs, and audit events in Supabase. It does not store raw
voice recordings, camera frames, eye videos, transcripts, or placeholder rows
for research models that did not execute.

After the project is linked, run:

```sh
cd /Users/biswajitacharya/Documents/v4
npx supabase config push --yes --project-ref poutjcphymgsfsuklokx
npx supabase migration list --linked
npx supabase db push --linked
```

`supabase/config.toml` pins `[storage.vector] enabled = false` so config push
does not try to enable paid Vector Buckets on a free project.

The migration enables Row Level Security on every app table and scopes reads and
writes to `auth.uid()`. Keep the service-role key out of the iOS app; only Edge
Functions should use it.

## Production checks

- Verify signup, confirmation OTP, resend, sign-in, recovery OTP or recovery
  link, reset, refresh-token rotation, sign-out, and deletion on a physical
  device.
- Keep email confirmations enabled in Supabase. If confirmations are disabled,
  signup may return a session immediately, but Venture's production flow is
  designed around inbox verification.
- Update App Store privacy answers to disclose name and email collection.
- Publish a support URL and privacy-policy URL.
- Review Supabase Auth logs, SMTP bounce handling, abuse controls, and backups.
- Do not store raw voice recordings, camera frames, eye videos, transcripts, or
  raw HealthKit samples in Supabase. Store extracted metrics and model outputs
  only.
