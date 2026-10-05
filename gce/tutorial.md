# 9ai-ext-google: Owner SA for remote manage

This tutorial runs after `./cloudshell-start.sh` (or a public-repo Open in
Cloud Shell clone). Private GitHub needs `gh auth login` before clone — Cloud
Shell disables git username prompts on auto-clone. Non-Google clones also
start without default GCP credentials — select a billed project first, then
bootstrap the Owner service account.

## Select a project

Pick (or create) a Google Cloud project with billing enabled. This attaches
the project to Cloud Shell so `gcloud` can create service accounts and IAM
bindings.

<walkthrough-project-setup billing></walkthrough-project-setup>

## Bootstrap Owner service account

Creates or reuses `9ai-remote-owner`, grants `roles/owner`, and writes
`./9ai-remote-owner.key.json` (do not commit).

```bash
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh && ./cloudshell-bootstrap.sh
```

## Verify

```bash
./iam.sh show
```

Confirm the SA email and that `roles/owner` is listed.

## Use the key remotely

Download or copy `9ai-remote-owner.key.json` out of Cloud Shell, then on a
laptop or CI host:

```bash
gcloud auth activate-service-account --key-file=./9ai-remote-owner.key.json
```

Store the key in vault or a secrets manager. Revoke unused keys with
`gcloud iam service-accounts keys list` / `delete`.

Without Cloud Shell, from any machine with `gcloud` and your user Owner login:

```bash
./iam.sh ensure-owner-sa
```
