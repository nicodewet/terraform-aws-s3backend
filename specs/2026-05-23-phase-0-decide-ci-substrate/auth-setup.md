# Local AWS Auth Setup — Phase 0 PoC

One-time setup for the maintainer's workstation to reach the disposable
AWS sub-account via IAM Identity Center (formerly AWS SSO). Once this is
done, `aws sso login` produces ~8h ephemeral creds — nothing long-lived
on disk and nothing in the repo. Aligned with [[requirements]] §Constraints
("no long-lived credentials in the repo").

**Scope:** local workstation → disposable sub-account, for running the
Phase 0 PoC. CI/GitHub-Actions auth is Phase 1 (OIDC), out of scope here.

## What you need before starting

- **AWS CLI v2** installed locally (Identity Center support requires v2,
  not v1). Verify: `aws --version` shows `aws-cli/2.x`.
- **Admin access to your AWS Organization's management account** (you
  need this to confirm or create the permission set and assignment).
- **Account ID of the disposable sub-account** (12-digit number, visible
  in the AWS Console > Organizations).
- **Your Identity Center start URL** (looks like
  `https://d-xxxxxxxxxx.awsapps.com/start` — visible in the Identity
  Center console under "Settings" in the management account).
- **The Identity Center region** (where Identity Center itself is
  enabled — often `us-east-1` even when your workloads live elsewhere).

## Step 1 — In Identity Center (management account, one-time)

Goal: a permission set that, when assumed in the disposable sub-account,
gives you enough to create + destroy every resource the module uses.

1.1. Sign in to the management account, open **IAM Identity Center**.

1.2. **Permission sets** → use the AWS-managed `AdministratorAccess`
permission set (it's a predefined option Identity Center offers out of
the box — no need to author a custom one for a disposable account). If
you prefer a custom-named set (e.g. `DisposableAccountAdmin`) you can
create one instead — just attach the AWS-managed `AdministratorAccess`
policy and set an 8-hour session duration (the default 1h is too short
for iterative work). Either way, the role provisioned in the sub-account
is what matters downstream.

**Why `AdministratorAccess` for this account specifically:** The
disposable sub-account exists only for this PoC and (later) CI. Its
contents are destroyed after every run. Trying to scope a least-privilege
permission set here is theater — the blast radius is already bounded by
the account boundary itself. Save least-privilege effort for the IAM
role *the module creates inside* the account, which is exactly what
`iam.tf` already does.

1.3. **Create an Identity Center user to assign** (skip if one already
exists). On a fresh Identity Center there are no users yet, so the
assignment in 1.4 has nothing to pick. Create one now:

- Left nav → **Users** → **Add user**.
- **Username**: `nicodewet` (or your preference — this is what you'll
  sign in with at the SSO start URL).
- **Email address**: your real email. Identity Center sends a
  verification/activation link here.
- **First name**, **Last name**, **Display name**: real values.
- **Password**: keep the default — *"Send an email to this user with
  password setup instructions"*. Click **Next**.
- **Add user to groups**: skip and click **Next**. A single-user PoC
  doesn't need a group; you can add one later if you grow the team.
- Review → **Add user**.
- Open your email, click the activation link, set a password, and
  complete MFA enrolment when prompted (Identity Center requires MFA
  by default — a virtual authenticator app like 1Password or Authy is
  fine).

**Why a fresh Identity Center starts empty:** Identity Center can
federate from an external IdP (Okta, Entra, Google Workspace) or use
its own built-in directory. In a fresh setup with no external IdP,
the built-in directory has zero users until you add one. The root
user of the management account is *not* an Identity Center user —
those are separate identity systems.

1.4. **AWS accounts** → tick the disposable sub-account → top right
**Assign users or groups** → pick the user from 1.3 → pick the
permission set from 1.2 → Submit. Provisioning takes ~30 seconds;
the page should show "Completed" before you move on.

1.5. Note the **permission-set role name** that Identity Center provisions
in the sub-account — it'll look like
`AWSReservedSSO_AdministratorAccess_<random-suffix>` (or
`AWSReservedSSO_<your-permission-set-name>_<random-suffix>` if you used a
custom one). You won't type this; the AWS CLI discovers it. Just be aware
it exists.

## Step 2 — On your workstation (one-time)

2.1. Run the interactive configurator:

```bash
aws configure sso
```

Answer the prompts:

| Prompt | Value |
|---|---|
| SSO session name (recommended) | `nicodewet` (or any short name) |
| SSO start URL | the start URL from prereqs |
| SSO region | the Identity Center region from prereqs |
| SSO registration scopes | accept the default (`sso:account:access`) |

A browser tab opens for one-time device authorization. Approve it.

Back in the terminal, you'll be shown a list of accounts you have access
to. Pick the **disposable sub-account**. Then pick the permission set
(`AdministratorAccess`, or your custom set from 1.2). If only one account
and one role are available, the CLI selects them automatically.

| Prompt | Value |
|---|---|
| CLI default client Region | `ap-southeast-2` (Sydney — matches the existing exercises) |
| CLI default output format | `json` |
| CLI profile name | `s3backend-poc` |

This writes a profile block to `~/.aws/config`. Nothing sensitive is
stored — just the SSO URL, the account ID, the permission-set name, and
the profile name.

2.2. Verify the profile works:

```bash
aws sts get-caller-identity --profile s3backend-poc
```

Expected output: a JSON blob whose `Account` field matches the
disposable sub-account ID, and whose `Arn` field includes
`assumed-role/AWSReservedSSO_*` (e.g.
`AWSReservedSSO_AdministratorAccess_<suffix>`). If you see this, auth is
wired correctly.

If you get `Error loading SSO Token: Token for ... does not exist`,
just run `aws sso login --profile s3backend-poc` first.

## Step 3 — Day-to-day flow (every working session)

Before running the PoC:

```bash
aws sso login --profile s3backend-poc
export AWS_PROFILE=s3backend-poc
export AWS_REGION=ap-southeast-2
```

`aws sso login` opens a browser, you approve, and you get ~8h of
ephemeral creds cached in `~/.aws/sso/cache/`. The PoC script
(`ci/poc-decide-ci-substrate.sh`, added in a later commit on this
branch) will read `AWS_PROFILE` and `AWS_REGION` from the environment.

When the session expires you'll see a credential error from the script
or from `aws` — just run `aws sso login --profile s3backend-poc` again
and retry. There's nothing to rotate, nothing to revoke.

## Why this satisfies the spec

| [[requirements]] constraint | How SSO satisfies it |
|---|---|
| "No long-lived credentials in the repo" | Nothing is in the repo. `~/.aws/config` (outside the repo) has metadata only. The SSO cache (also outside the repo) holds short-lived STS tokens. |
| "PoC reads creds from the environment" | `AWS_PROFILE` env var points at the profile; the AWS SDK resolves the rest. |
| "Cleanup is mandatory" | Orthogonal to auth, but SSO's session expiry is a useful belt-and-braces — even if you walk away mid-run, the creds rot in 8h. |

## Troubleshooting

- **`The SSO session associated with this profile has expired`** —
  Run `aws sso login --profile s3backend-poc`.
- **`Unable to locate credentials`** — `AWS_PROFILE` is unset. Re-export
  it, or pass `--profile s3backend-poc` to the failing command.
- **`AccessDenied` on a module resource (KMS, IAM, etc.)** — Permission
  set doesn't grant enough. Confirm Step 1.2 attached
  `AdministratorAccess`, not a smaller policy.
- **`InvalidClientTokenId`** — Usually means the profile is pointing at
  the wrong account or the SSO token is for a different account.
  Re-run `aws configure sso` from scratch with a clean profile name.
