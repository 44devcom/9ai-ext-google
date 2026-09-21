# ext/google

Invariants for this folder live in [`.rules/RULES.md`](.rules/RULES.md); what
dependents may rely on lives in [`.rules/CONTRACT.md`](.rules/CONTRACT.md).

Console-only GCP vendor unit under EXT-004: no Python distribution and no
`@platform/*` kit. The operator surface is the Docker console in
[`console/`](console/).

See [`console/README.md`](console/README.md) for build, vault material
projection, interactive / one-shot usage, and Artifact Registry helpers.

## Remotes

Origin fetch is GitLab. A single `git push` dual-pushes GitLab then GitHub via
two origin `pushurl`s, so both `check` / Release pipelines run. `github` is a
one-forge escape hatch.

Replace `9ai-ext-google` with this repo's name (for example `9ai-core-events`).

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
uv sync --all-extras --group dev && uv run pytest -q

# Web
pnpm install && pnpm test   # and/or pnpm check-types
```

First-party `platform-*` / `@platform/*` deps resolve from **GitLab git URLs**
on `git.44dev.com` (same host as `origin` fetch), not a 44dev-v11 workspace.
Those sibling repos are private, so Git needs credentials for
`https://git.44dev.com/` (see [Git auth](#git-auth-private-sibling-clones)).

Optional local override while hacking two clones side by side (not a committed
default):

```toml
# pyproject.toml [tool.uv.sources]
# platform-events = { path = "../9ai-core-events", editable = true }
```

```bash
pnpm add @platform/tsconfig@git+https://git.44dev.com/44devcom/9ai-web-tsconfig.git
uv add platform-events --git https://git.44dev.com/44devcom/9ai-core-events.git
```

## Git auth (private sibling clones)

`uv sync` / `pnpm install` clone sibling `9ai-*` repos over HTTPS. Configure
`insteadOf` (or a `glab` / `gh` credential helper) so Git can fetch them:

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

If group token inbound cannot be enabled, set one `PACKAGE_GIT_TOKEN` secret
on both forges.
