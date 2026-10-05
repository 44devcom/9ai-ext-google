# 9ai-ext-google: Owner SA for remote manage

This tutorial runs after **Open in Cloud Shell**. There is no project picker.
`./cloudshell-bootstrap.sh` selects an active GCP project, creates or reuses
`nineai-remote-owner`, and prints the key JSON (also written to
`./nineai-remote-owner.key.json`; do not commit).

If auto-clone failed (`terminal prompts disabled` on a private fork):

```bash
gh auth login -p https -w && chmod 755 cloudshell-start.sh && ./cloudshell-start.sh
```

## Write Owner key

```bash
chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh && ./cloudshell-bootstrap.sh
```

Copy the JSON from the terminal, or download `nineai-remote-owner.key.json`.

On a laptop or CI host:

```bash
gcloud auth activate-service-account --key-file=./nineai-remote-owner.key.json
```

Store the key in vault or a secrets manager. Revoke unused keys with
`gcloud iam service-accounts keys list` / `delete`.
