#!/bin/bash
# Deploy the latest qiita-web build of lucaspatel/Qiita feat/web-ui to ~/qiita-web-dev/current. Run by qiita-web-deploy.timer.
# The branch's code (vite config, npm deps) only ever runs inside a throwaway, capability-less node container.
set -euo pipefail
REPO=${QIITA_WEB_REPO:-https://github.com/lucaspatel/Qiita.git}
BRANCH=${QIITA_WEB_BRANCH:-feat/web-ui}
ROOT=${QIITA_WEB_ROOT:-$HOME/qiita-web-dev}
IMAGE=${QIITA_WEB_NODE_IMAGE:-node:22-alpine}
CONFIG=${QIITA_CONFIG:-$HOME/.qiita/config.toml}
WRAPPER=$(dirname "$(readlink -f "$0")")/vite.config.deploy.ts
KEEP=3
log() { echo "$(date "+%F %T") $*"; }

live() { basename "$(readlink "$ROOT/current" 2>/dev/null)" 2>/dev/null; }
# A release is a commit plus the environments baked into it, so editing config.toml also redeploys.
cfg=$(cat "$CONFIG" "$WRAPPER" | sha256sum | cut -c1-8)
sha=$(git ls-remote "$REPO" "refs/heads/$BRANCH" | cut -f1)
[ -n "$sha" ] || { log "$BRANCH not found on $REPO"; exit 1; }
[ "$(live)" = "$sha-$cfg" ] && exit 0
[ -e "$ROOT/failed/$sha-$cfg" ] && exit 0

mkdir -p "$ROOT/releases" "$ROOT/failed"
src=$(mktemp -d "$ROOT/src.XXXXXX"); out=$ROOT/releases/.build-$$
trap 'rm -rf "$src" "$out"' EXIT
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$src"
sha=$(git -C "$src" rev-parse HEAD); id=$sha-$cfg
[ "$(live)" = "$id" ] && exit 0
mkdir -p "$out"
log "building $id"
if ! docker run --rm --pull missing --user "$(id -u):$(id -g)" -e HOME=/tmp \
    --cap-drop ALL --security-opt no-new-privileges --memory 4g --cpus 2 \
    --read-only --tmpfs /tmp:exec,size=3g \
    -v "$src/qiita-web:/src:ro" -v "$CONFIG:/qiita-config.toml:ro" -v "$WRAPPER:/vite.config.deploy.ts:ro" \
    -v "$out:/out" -e QIITA_CONFIG=/qiita-config.toml "$IMAGE" \
    sh -c 'cp -r /src /tmp/w && cp /vite.config.deploy.ts /tmp/w/ && cd /tmp/w &&
      if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi &&
      npx vite build --config vite.config.deploy.ts && cp -r build/. /out/' \
  || [ ! -f "$out/index.html" ]; then
  touch "$ROOT/failed/$id"; log "build of $id failed; staying on $(live || echo nothing)"; exit 1
fi
rm -rf "$ROOT/releases/$id" && mv "$out" "$ROOT/releases/$id"
ln -sfn "releases/$id" "$ROOT/current.new" && mv -T "$ROOT/current.new" "$ROOT/current"
log "deployed $id"
ls -1t "$ROOT/releases" | tail -n +$((KEEP + 1)) | while read -r old; do rm -rf "${ROOT:?}/releases/$old"; done
