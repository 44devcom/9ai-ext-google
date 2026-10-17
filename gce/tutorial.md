# 9ai-ext-google: Owner SA for remote manage

This tutorial runs after **Open in Cloud Shell**. Bootstrap starts with the
workspace (no project picker): it selects an active GCP project, creates or
reuses `nineai-remote-owner`, and prints the key JSON (also written to
`./nineai-remote-owner.key.json`; do not commit).

If auto-clone failed (`terminal prompts disabled` on a private fork):

```bash
gh auth login -p https -w && chmod 755 cloudshell-start.sh && ./cloudshell-start.sh
```

## Owner key

If the JSON is not in the terminal yet, run:

```bash
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh && ./cloudshell-bootstrap.sh
```

Copy the JSON from the terminal, or download `nineai-remote-owner.key.json`.

## Keys blocked by org policy

If bootstrap prints `key creation blocked by org policy`, your organization
disallows service account keys (`constraints/iam.disableServiceAccountKeyCreation`).
The Owner SA and `roles/owner` binding are still created; bootstrap grants your
active login `roles/iam.serviceAccountTokenCreator` on that SA and prints
`gcloud config set auth/impersonate_service_account ...` on stderr.

In Cloud Shell you can keep using your user login for `gcloud` in this session.
On another machine, run `gcloud auth login`, then follow the impersonation
block from bootstrap (or re-run `./cloudshell-bootstrap.sh`).

The Docker console (`console/run.sh`) still needs a key file or
`GCP_CREDENTIALS_JSON`; impersonation is for host `gcloud` only.

On a laptop or CI host (when keys are allowed):

```bash
gcloud auth activate-service-account --key-file=./nineai-remote-owner.key.json
```

Store the key in vault or a secrets manager. Revoke unused keys with
`gcloud iam service-accounts keys list` / `delete`.
