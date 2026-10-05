# ext/google

Invariants for this folder live in [`.rules/RULES.md`](.rules/RULES.md); what
dependents may rely on lives in [`.rules/CONTRACT.md`](.rules/CONTRACT.md).

GCP vendor unit under EXT-004: no Python distribution and no `@platform/*`
kit. Surfaces:

- Docker console in [`console/`](console/)
- Idempotent GCE helpers in [`gce/`](gce/) (`gce/lib.sh`) for Cloud Shell /
  operator deploy scripts (create-or-reuse network, address, firewall, VM)
- Owner service-account bootstrap in [`gce/iam.sh`](gce/iam.sh) for remote
  manage

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/44devcom/9ai-ext-google&cloudshell_git_branch=master&cloudshell_workspace=gce&cloudshell_tutorial=tutorial.md&cloudshell_print=cloudshell-print.txt)

The button clones this repo, opens `gce/`, prints a short banner, and launches
[`gce/tutorial.md`](gce/tutorial.md). Run `./cloudshell-bootstrap.sh`: it picks
an active GCP project (no picker), writes the Owner SA key, and prints the
JSON. If auto-clone fails (`terminal prompts disabled` on a private fork),
run [`gce/cloudshell-start.sh`](gce/cloudshell-start.sh) after `gh auth login`
(that path also runs bootstrap). Without Cloud Shell, use
`./gce/iam.sh ensure-owner-sa` on any host with your user Owner login.

See [`console/README.md`](console/README.md) for build, vault material
projection, interactive / one-shot usage, and Artifact Registry helpers.
See [`gce/README.md`](gce/README.md) for the ensure/delete API and IAM
commands.

## Remotes

Origin fetch is GitLab. A single `git push` dual-pushes GitLab then GitHub via
two origin `pushurl`s, so both `check` / Release pipelines run. `github` is a
one-forge escape hatch.

```bash
git remote rename origin github
git remote add origin https://git.44dev.com/44devcom/9ai-ext-google.git
# First --add --push replaces the implicit "fetch URL is also push" with an explicit list.
# Both URLs must be added or GitLab would stop receiving pushes.
git remote set-url --add --push origin https://git.44dev.com/44devcom/9ai-ext-google.git
git remote set-url --add --push origin https://github.com/44devcom/9ai-ext-google.git
git push -u origin master
```

Expected `git remote -v`:

```
github  https://github.com/44devcom/9ai-ext-google.git (fetch)
github  https://github.com/44devcom/9ai-ext-google.git (push)
origin  https://git.44dev.com/44devcom/9ai-ext-google.git (fetch)
origin  https://git.44dev.com/44devcom/9ai-ext-google.git (push)
origin  https://github.com/44devcom/9ai-ext-google.git (push)
```

Push order is GitLab then GitHub. If the first URL fails, Git stops. GitLab CI
tag pushes use `CI_JOB_TOKEN` against GitLab only.

## Standalone install

This repo is a single package root. After clone:

```bash
# Python
uv sync --group dev && uv run pytest -q

# Web
pnpm install && pnpm test   # and/or pnpm check-types

# Console
test -f console/Dockerfile
```

First-party `platform-*` / `@platform/*` deps resolve from **GitLab git URLs**
on `git.44dev.com` (same host as `origin` fetch), not a 44dev-v7 workspace.
Those sibling repos are private, so Git needs credentials for
`https://git.44dev.com/` (see [Git auth](#git-auth-private-sibling-clones)).

## Git auth (private sibling clones)

`uv sync` / `pnpm install` clone sibling `9ai-*` repos over HTTPS. Configure
`insteadOf` (or a credential helper) so Git can fetch them:

```bash
# GitLab PAT, deploy token, or PACKAGE_GIT_TOKEN
git config --global url."https://oauth2:${GITLAB_TOKEN}@git.44dev.com/".insteadOf "https://git.44dev.com/"

# Same secret name CI uses on GitHub Actions
git config --global url."https://x-access-token:${PACKAGE_GIT_TOKEN}@git.44dev.com/".insteadOf "https://git.44dev.com/"
```

CI does the same rewrite:

- **GitLab:** `gitlab-ci-token:${CI_JOB_TOKEN}` when group job-token inbound
  access is enabled for `44devcom`; otherwise `PACKAGE_GIT_TOKEN`.
- **GitHub Actions:** `secrets.PACKAGE_GIT_TOKEN` with
  `url."https://x-access-token:${PACKAGE_GIT_TOKEN}@git.44dev.com/".insteadOf "https://git.44dev.com/"`.
