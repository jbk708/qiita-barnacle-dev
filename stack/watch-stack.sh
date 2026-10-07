#!/bin/bash
# Restart the stack when a service dies: a killed/crashed service or "shutting down" in the running job's log
# after it came up, or 3 failed control-plane health checks in a row. Stops Postgres cleanly, submits a replacement
# that waits for the old job to end, repoints any other pending stack job at it, then cancels the old job.
# At most 3 restarts per 24 h.
# Usage: nohup setsid stack/watch-stack.sh >/dev/null 2>&1 &
#   QDEV_RESTART_ARGS overrides the sbatch shape; QDEV_STACK_SCRIPT the job script (default: this repo's).
source "${QDEV_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config.sh"
: "${QDEV_ACCOUNT:?set QDEV_ACCOUNT to your Slurm account}"
B=$QDEV_ROOT; L=$B/logs; LOG=$L/watch-stack.log; source $B/env/ports
ARGS=${QDEV_RESTART_ARGS:--p gpu -c 16 --mem=88G -t 3-00:00:00}
SCRIPT=${QDEV_STACK_SCRIPT:-$QDEV_REPO/stack/stack.sbatch}
log() { echo "$(date "+%F %T") $*" >> $LOG; }
on_node() { srun --jobid=$1 --overlap -n 1 -c 1 --mem=1G bash -c "$2"; }
echo $$ > $L/watch-stack.pid
log "started (restart shape: $ARGS; script: $SCRIPT)"
fails=0
while :; do
  J=$(squeue -u $USER -h -n qiita-dev-stack -t R -o %i | head -1)
  if [ -z "$J" ]; then sleep 300; continue; fi
  SL=$L/stack-$J.log
  if ! grep -q "\[stack\] up" $SL 2>/dev/null; then fails=0; sleep 300; continue; fi
  reason=$(sed -n '/\[stack\] up/,$p' $SL | grep -m1 -E "Killed|Segmentation fault|a service exited|\[stack\] shutting down")
  if [ -z "$reason" ]; then
    code=$(on_node $J "curl -s -m 15 -o /dev/null -w %{http_code} http://127.0.0.1:$CP/healthz" 2>/dev/null)
    if [ "$code" = 200 ]; then fails=0; else fails=$((fails + 1)); fi
    [ $fails -ge 3 ] && reason="control plane health check failed 3 times (last: $code)"
  fi
  if [ -n "$reason" ]; then
    recent=$(awk -v t=$(date -d '24 hours ago' +%s) '/ restart: /{ split($1" "$2, a, /[- :]/); if (mktime(a[1]" "a[2]" "a[3]" "a[4]" "a[5]" "a[6]) > t) n++ } END { print n + 0 }' $LOG)
    if [ "$recent" -ge 3 ]; then log "job $J failed ($reason) but 3 restarts in 24 h already; stopping"; exit 1; fi
    log "job $J failed: $reason"
    on_node $J "p=\$(pgrep -u $USER -x postgres -o); [ -n \"\$p\" ] && kill -INT \$p; for i in \$(seq 60); do pgrep -u $USER -x postgres >/dev/null || exit 0; sleep 1; done; exit 1" \
      && log "postgres stopped" || log "postgres did not stop within 60 s"
    N=$(sbatch --parsable $ARGS -A "$QDEV_ACCOUNT" -J qiita-dev-stack --signal=B:TERM@120 -o "$L/stack-%j.log" \
          --wrap "while squeue -h -j $J 2>/dev/null | grep -q .; do sleep 10; done; exec bash $SCRIPT")
    for P in $(squeue -u $USER -h -n qiita-dev-stack -t PD -o %i); do
      [ "$P" = "$N" ] || scontrol update jobid=$P dependency=afterany:$N
    done
    scancel $J
    log "restart: $J -> $N ($ARGS)"
    fails=0
  fi
  sleep 300
done
