#!/bin/bash
# Run the qiita CLI against the dev stack from the login node: ./qiita-dev.sh submit-ena-import PRJDB13464
source "${QDEV_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config.sh"
B=$QDEV_ROOT
JOB=$(squeue -u $USER -h -n qiita-dev-stack -t R -o %i | head -1)
[ -n "$JOB" ] || { echo "stack job not running"; exit 1; }
source $B/env/ports
exec srun --jobid=$JOB --overlap -n 1 -c 1 --mem=2G env QIITA_CONTROL_PLANE_URL=http://127.0.0.1:$CP \
  QIITA_TOKEN="$(cat $B/env/master.token)" $B/Qiita/qiita-control-plane/.venv/bin/qiita "$@"
