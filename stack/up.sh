#!/bin/bash
# Submit the stack job. Extra args go to sbatch: ./stack/up.sh -p short -c 16 --mem=100G -t 1-00:00:00
source "$(cd "$(dirname "$0")/.." && pwd)/config.sh"
: "${QDEV_ACCOUNT:?set QDEV_ACCOUNT to your Slurm account}"
mkdir -p "$QDEV_ROOT/logs"
exec sbatch -p long -A "$QDEV_ACCOUNT" -o "$QDEV_ROOT/logs/stack-%j.log" "$@" "$QDEV_REPO/stack/stack.sbatch"
