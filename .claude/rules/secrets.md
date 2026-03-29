# TCP Secrets & Sensitive Data

## Never Commit

- API keys, tokens, passwords, or credentials of any kind
- `.env` files (`.env`, `.env.local`, `.env.production`, etc.)
- Private keys or certificates (`.pem`, `.key`, `.p12`, `.pfx`)
- Database connection strings with credentials
- OAuth client secrets
- Webhook URLs with embedded tokens
- Personal information (real names, emails, addresses, phone numbers)

## Where Secrets Go

- Local development: `.env` file (already in `.gitignore`)
- Godot export credentials: `export_credentials.cfg` (already in `.gitignore`)
- CI/CD: repository secrets or environment variables, never checked in
- Shared team secrets: use a secrets manager, never a file in the repo

## Config Values Are Not Secrets

Game balance numbers, thresholds, and tuning parameters in `config/` JSON files are public data. They are intentionally readable and overridable by mods. Do not confuse game config with application secrets.

## Enforcement

`script/checks/no_secrets` wraps [gitleaks](https://github.com/gitleaks/gitleaks) (160+ secret patterns, actively maintained). Runs in both `script/validate` and the pre-commit hook. Install: `brew install gitleaks`. If it flags a false positive, add `# gitleaks:allow` as a comment on that line, or add a rule to `.gitleaks.toml`.

## .gitignore

The `.gitignore` already excludes: `.env`, `export_credentials.cfg`, `.claude/settings.local.json`, `.claude/projects/*/memory`. If you add a new category of sensitive file, add it to `.gitignore` before anything else.
