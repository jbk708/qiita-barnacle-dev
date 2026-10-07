#!/bin/bash
# Point qiita-tunnel.service at the barnacle node running the dev stack. Run by qiita-node.timer.
# Follows the stack only; barnacle's watch-stack.sh owns restarts, so this never submits or cancels jobs.
set -uo pipefail
C=${QIITA_NODE_CONFIG:-$HOME/.config/qiita-node}
source "$C/qiita-node.env"
TUNNEL_ENV=$C/tunnel-qiita.env
log() { echo "$(date "+%F %T") $*"; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

jobs=$("${SSH[@]}" "$BARNACLE" \
  "squeue -u $BARNACLE_USER -h -n qiita-dev-stack -t R -o '%i %N' | sort -rn" 2>&1) \
  || { log "squeue via $BARNACLE failed: $jobs"; exit 1; }
node=
while read -r job host; do
  [ -n "$job" ] || continue
  # Newest running job whose stack is up and whose control plane answers.
  code=$("${SSH[@]}" "$host" \
    "grep -q '\[stack\] up' $STACK_LOG_DIR/stack-$job.log && curl -s -m 10 -o /dev/null -w %{http_code} http://127.0.0.1:$CP_PORT/healthz" 2>/dev/null)
  [ "$code" = 200 ] && { node=$host; break; }
done <<< "$jobs"
[ -n "$node" ] || { log "no healthy qiita-dev-stack job (running: ${jobs:-none}); tunnel left as is"; exit 0; }

current=$(sed -n 's/^QIITA_NODE=//p' "$TUNNEL_ENV" 2>/dev/null)
if [ "$node" != "$current" ]; then
  printf 'QIITA_NODE=%s\n' "$node" > "$TUNNEL_ENV.tmp" && mv "$TUNNEL_ENV.tmp" "$TUNNEL_ENV"
  systemctl --user restart qiita-tunnel.service
  log "stack moved ${current:-<none>} -> $node; tunnel restarted"
elif ! systemctl --user is-active -q qiita-tunnel.service; then
  systemctl --user restart qiita-tunnel.service
  log "tunnel was down; restarted on $node"
fi
