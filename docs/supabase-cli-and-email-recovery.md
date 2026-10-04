# Supabase CLI and Email Recovery

Use these commands from the repository root. Running them from `~` makes the CLI
miss `supabase/config.toml` and the Edge Function entrypoint.

```sh
cd /Users/biswajitacharya/Documents/v4
```

If the CLI says it cannot read `~/.supabase/profile`, sign in again:

```sh
npx supabase login
```

Then confirm the project link:

```sh
npx supabase link --project-ref poutjcphymgsfsuklokx
npx supabase migration list --linked
npx supabase functions list --project-ref poutjcphymgsfsuklokx
```

Deploy backend changes from the repo root:

```sh
npx supabase config push --yes --project-ref poutjcphymgsfsuklokx
npx supabase db push --linked
npx supabase functions deploy delete-account --project-ref poutjcphymgsfsuklokx
```

## Auth Email SMTP

Use a verified sender from a real email provider. Do not leave
`noreply@yourdomain.com` unless that domain is verified with SPF, DKIM, and
DMARC.

Recommended Resend settings:

- sender email address: `noreply@your-verified-domain.com`
- sender name: `Venture`
- host: `smtp.resend.com`
- port number: `587`
- minimum interval per user: `60`
- username: `resend`
- password: the Resend API key

SendGrid alternative:

- sender email address: `noreply@your-verified-domain.com`
- sender name: `Venture`
- host: `smtp.sendgrid.net`
- port number: `587`
- minimum interval per user: `60`
- username: `apikey`
- password: the SendGrid API key

After saving SMTP settings, test sign up, verification email delivery, password
reset email delivery, and the `venture://auth/reset` deep link on a real device.
