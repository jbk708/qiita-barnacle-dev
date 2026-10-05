#!/bin/bash
# Submit the build job (venvs, SIFs, data plane). Extra args go to sbatch.
source "$(cd "$(dirname "$0")/.." && pwd)/config.sh"
: "${QDEV_ACCOUNT:?set QDEV_ACCOUNT to your Slurm account}"
mkdir -p "$QDEV_ROOT/logs"
exec sbatch -A "$QDEV_ACCOUNT" -o "$QDEV_ROOT/logs/build-%j.log" "$@" "$QDEV_REPO/stack/build.sbatch"
