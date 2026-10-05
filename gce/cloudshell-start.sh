#!/usr/bin/env bash
# Fallback when Open in Cloud Shell auto-clone fails (private fork; GitHub
# prompts disabled). Public 9ai-ext-google uses the README OiCS button instead.
#
#   gh auth login -p https -w
#   gh repo clone 44devcom/9ai-ext-google ~/9ai-ext-google
#   cd ~/9ai-ext-google/gce && ./cloudshell-start.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-44devcom/9ai-ext-google}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/${REPO_SLUG}.git}"
DEST="${DEST:-${HOME}/9ai-ext-google}"
LAUNCH_TUTORIAL="${LAUNCH_TUTORIAL:-1}"

die() { echo "error: $*" >&2; exit 1; }

ensure_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "need an interactive terminal to ask for GitHub credentials (run from Cloud Shell terminal)"
  fi
}

github_reachable() {
  git ls-remote --heads "$REPO_HTTPS" HEAD >/dev/null 2>&1
}

ensure_github_auth() {
  if github_reachable; then
    echo "github: repo reachable (public or already authenticated)"
    return 0
  fi

  echo "github: ${REPO_SLUG} is private or unreachable without credentials"
  ensure_tty

  if command -v gh >/dev/null 2>&1; then
    if ! gh auth status >/dev/null 2>&1; then
      echo "Starting GitHub login (browser or token). Choose HTTPS."
      gh auth login -p https -h github.com -w || gh auth login -p https -h github.com
    fi
    gh auth setup-git >/dev/null 2>&1 || true
    if github_reachable || gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
      echo "github: authenticated via gh"
      return 0
    fi
  fi

  echo "Paste a GitHub personal access token with 'repo' scope (input hidden),"
  echo "or press Enter to abort and run: gh auth login"
  local token
  read -r -s -p "GitHub token: " token
  echo
  [[ -n "$token" ]] || die "no token; run gh auth login then re-run this script"

  git config --global credential.helper store
  printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n\n' "$token" \
    | git credential approve
  unset token

  github_reachable || die "still cannot access ${REPO_HTTPS}; check token scopes (repo)"
  echo "github: authenticated via token"
}

ensure_clone() {
  if [[ -d "${DEST}/.git" ]]; then
    echo "repo: ${DEST} exists; fetching"
    git -C "$DEST" fetch --depth 1 origin master >/dev/null 2>&1 \
      || git -C "$DEST" fetch --depth 1 origin main >/dev/null 2>&1 \
      || true
    git -C "$DEST" checkout master >/dev/null 2>&1 \
      || git -C "$DEST" checkout main >/dev/null 2>&1 \
      || true
    git -C "$DEST" reset --hard origin/master >/dev/null 2>&1 \
      || git -C "$DEST" reset --hard origin/main >/dev/null 2>&1 \
      || true
    return 0
  fi

  echo "cloning ${REPO_HTTPS} -> ${DEST}"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "$REPO_SLUG" "$DEST"
  else
    git clone --depth 1 "$REPO_HTTPS" "$DEST"
  fi
}

launch_tutorial() {
  local gce="${DEST}/gce"
  [[ -d "$gce" ]] || die "missing ${gce}"
  cd "$gce"
  chmod 755 lib.sh iam.sh cloudshell-bootstrap.sh cloudshell-start.sh 2>/dev/null || true
  if [[ "$LAUNCH_TUTORIAL" != 1 ]]; then
    echo "cwd=${gce} (tutorial skipped; LAUNCH_TUTORIAL=0)"
    return 0
  fi
  if command -v cloudshell >/dev/null 2>&1; then
    cloudshell launch-tutorial tutorial.md
  elif command -v teachme >/dev/null 2>&1; then
    teachme tutorial.md
  else
    echo "Tutorial launcher not found. Open tutorial.md manually or run:"
    echo "  ./cloudshell-bootstrap.sh"
  fi
}

ensure_github_auth
ensure_clone
launch_tutorial
echo "next: complete project setup in the tutorial, then ./cloudshell-bootstrap.sh"
