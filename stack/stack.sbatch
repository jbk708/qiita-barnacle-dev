#!/bin/bash
#SBATCH -J qiita-dev-stack
#SBATCH -c 32
#SBATCH --mem=200G
#SBATCH -t 14-00:00:00
#SBATCH --signal=B:TERM@120
# Personal Qiita dev stack: Postgres (apptainer) + data plane + control plane + orchestrator
# (COMPUTE_BACKEND=local), all on localhost of this node. Submit with stack/up.sh.
set -euo pipefail
: "${QDEV_ROOT:?submit with stack/up.sh}"
B=$QDEV_ROOT; Q=$B/Qiita; E=$B/env; L=$B/logs
export PATH=$HOME/.local/bin:$PATH
source $E/ports
RUN=/dev/shm/qiita-dev-$SLURM_JOB_ID; mkdir -p $RUN/pgsock $RUN/dp-home
PG="apptainer exec -B $B/pg:/pgdata -B $RUN/pgsock:/var/run/postgresql $B/postgres_17.sif"
PIDS=()

cleanup() {
  echo "[stack] shutting down"
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
  $PG pg_dump -h localhost -p $PGPORT -Fc qiita > $B/pg-dumps/qiita-final.dump 2>/dev/null || true
  $PG pg_dump -h localhost -p $PGPORT -Fc qiita_ducklake > $B/pg-dumps/ducklake-final.dump 2>/dev/null || true
  kill -INT "${PGPID:-0}" 2>/dev/null && wait "$PGPID" 2>/dev/null || true
  rm -rf $RUN
}
trap cleanup EXIT

wait_http() { for _ in $(seq 120); do curl -fsS -m 5 "$1" >/dev/null 2>&1 && return 0; sleep 2; done; echo "[stack] timeout: $1"; return 1; }

echo "[stack] node $(hostname) job $SLURM_JOB_ID ports $(cat $E/ports)" | tee $L/current-node
if [ ! -f $B/pg/PG_VERSION ]; then
  chmod 700 $B/pg
  $PG initdb -D /pgdata -U "$USER" --auth=trust >> $L/pg-init.log
fi
$PG postgres -D /pgdata -p $PGPORT -c listen_addresses=localhost -k /var/run/postgresql \
  -c max_connections=200 -c shared_memory_type=sysv -c dynamic_shared_memory_type=sysv \
  >> $L/pg.log 2>&1 &
PGPID=$!
for _ in $(seq 60); do $PG pg_isready -q -h localhost -p $PGPORT && break; sleep 2; done
$PG pg_isready -h localhost -p $PGPORT
$PG psql -h localhost -p $PGPORT -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='qiita_ducklake'" | grep -q 1 \
  || $PG createdb -h localhost -p $PGPORT qiita_ducklake

set -a; source $E/control-plane.env; set +a
(cd $Q && make migrate) >> $L/migrate.log 2>&1
(cd $Q && make sync-actions) >> $L/migrate.log 2>&1
SLURM_NATIVE_PYTHON=$Q/qiita-compute-orchestrator/.venv/bin/python \
  bash $Q/scripts/stage-miint-extension.sh >> $L/miint-stage.log 2>&1

( set -a; source $E/data-plane.env; set +a; export HOME=$RUN/dp-home
  exec $Q/qiita-data-plane/target/release/qiita-data-plane ) >> $L/dp.log 2>&1 &
PIDS+=($!)
( set -a; source $E/control-plane.env; set +a; cd $Q/qiita-control-plane
  exec .venv/bin/uvicorn qiita_control_plane.main:app --host 127.0.0.1 --port $CP ) >> $L/cp.log 2>&1 &
PIDS+=($!)
wait_http http://127.0.0.1:$CP/healthz

if [ ! -f $E/master.token ]; then
  (set -a; source $E/control-plane.env; set +a; cd $Q/qiita-control-plane
   .venv/bin/python $QDEV_REPO/stack/seed_master_token.py $E/master.token)
fi
if [ ! -f $E/co-to-cp.token ]; then
  ( umask 077
    curl -fsS -X POST http://127.0.0.1:$CP/api/v1/admin/service-account \
      -H "Authorization: Bearer $(cat $E/master.token)" -H 'Content-Type: application/json' \
      -d '{"name":"compute","scopes":["sequence_range:mint","ticket:doget"]}' > $RUN/sa.json
    $Q/qiita-control-plane/.venv/bin/python -c "import json,sys; print(json.load(open(sys.argv[1]))['token'])" $RUN/sa.json > $E/co-to-cp.token
    rm -f $RUN/sa.json )
fi

( set -a; source $E/compute-orchestrator.env; set +a; export CO_TO_CP_TOKEN=$(cat $E/co-to-cp.token)
  cd $Q/qiita-compute-orchestrator
  exec .venv/bin/uvicorn qiita_compute_orchestrator.main:app --host 127.0.0.1 --port $CO ) >> $L/co.log 2>&1 &
PIDS+=($!)
wait_http http://127.0.0.1:$CO/healthz || true
echo "[stack] up: CP http://127.0.0.1:$CP  CO :$CO  DP :$DP  PG :$PGPORT"

( while sleep 86400; do
    $PG pg_dump -h localhost -p $PGPORT -Fc qiita > $B/pg-dumps/qiita-$(date +%F).dump
    $PG pg_dump -h localhost -p $PGPORT -Fc qiita_ducklake > $B/pg-dumps/ducklake-$(date +%F).dump
  done ) &
PIDS+=($!)

wait -n "${PIDS[@]:0:3}"
echo "[stack] a service exited; stopping"
