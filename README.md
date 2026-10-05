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

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?show=ide%2Cterminal)

This repo is **private**. Cloud Shell cannot prompt for GitHub credentials during
auto-clone (`terminal prompts disabled`), so the button opens a shell only —
it does **not** pass `cloudshell_git_repo`. After the terminal is ready, paste:

```bash
gh auth login -p https -w && gh repo clone 44devcom/9ai-ext-google ~/9ai-ext-google && cd ~/9ai-ext-google/gce && chmod 755 cloudshell-start.sh && ./cloudshell-start.sh
```

That asks for GitHub login, clones, and launches [`gce/tutorial.md`](gce/tutorial.md).
Select a billed project, then run `./cloudshell-bootstrap.sh` (Owner SA + key).
Re-entry from an existing clone: `cd ~/9ai-ext-google/gce && ./cloudshell-start.sh`.
Without Cloud Shell, use `./gce/iam.sh ensure-owner-sa` with your user Owner login.

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
