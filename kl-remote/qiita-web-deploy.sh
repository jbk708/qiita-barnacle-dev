#!/bin/bash
# Deploy the latest qiita-web build of lucaspatel/Qiita feat/web-ui to ~/qiita-web-dev/current. Run by qiita-web-deploy.timer.
# The branch's code (vite config, npm deps) only ever runs inside a throwaway, capability-less node container.
set -euo pipefail
REPO=${QIITA_WEB_REPO:-https://github.com/lucaspatel/Qiita.git}
BRANCH=${QIITA_WEB_BRANCH:-feat/web-ui}
ROOT=${QIITA_WEB_ROOT:-$HOME/qiita-web-dev}
IMAGE=${QIITA_WEB_NODE_IMAGE:-node:22-alpine}
KEEP=3
log() { echo "$(date "+%F %T") $*"; }

sha=$(git ls-remote "$REPO" "refs/heads/$BRANCH" | cut -f1)
[ -n "$sha" ] || { log "$BRANCH not found on $REPO"; exit 1; }
[ "$(basename "$(readlink "$ROOT/current" 2>/dev/null)")" = "$sha" ] && exit 0
[ -e "$ROOT/failed/$sha" ] && exit 0

mkdir -p "$ROOT/releases" "$ROOT/failed"
src=$(mktemp -d "$ROOT/src.XXXXXX"); out=$ROOT/releases/.$sha
trap 'rm -rf "$src" "$out"' EXIT
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$src"
sha=$(git -C "$src" rev-parse HEAD)
[ "$(basename "$(readlink "$ROOT/current" 2>/dev/null)")" = "$sha" ] && exit 0
mkdir -p "$out"
log "building $sha"
if ! docker run --rm --pull missing --user "$(id -u):$(id -g)" -e HOME=/tmp \
    --cap-drop ALL --security-opt no-new-privileges --memory 4g --cpus 2 \
    --read-only --tmpfs /tmp:exec,size=3g \
    -v "$src/qiita-web:/src:ro" -v "$out:/out" "$IMAGE" \
    sh -c 'cp -r /src /tmp/w && cd /tmp/w && if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi && npm run build && cp -r build/. /out/' \
  || [ ! -f "$out/index.html" ]; then
  touch "$ROOT/failed/$sha"; log "build of $sha failed; staying on $(basename "$(readlink "$ROOT/current" 2>/dev/null)" 2>/dev/null || echo nothing)"; exit 1
fi
mv "$out" "$ROOT/releases/$sha"
ln -sfn "releases/$sha" "$ROOT/current.new" && mv -T "$ROOT/current.new" "$ROOT/current"
log "deployed $sha"
ls -1t "$ROOT/releases" | tail -n +$((KEEP + 1)) | while read -r old; do rm -rf "${ROOT:?}/releases/$old"; done
