#!/bin/bash
# Build the Python venvs and the data plane (in a rust container; compute nodes have no g++).
#SBATCH -J qiita-dev-build
#SBATCH -p short
#SBATCH -c 32
#SBATCH --mem=64G
#SBATCH -t 04:00:00
set -euxo pipefail
: "${QDEV_ROOT:?submit with stack/build.sh}"
export PATH=$HOME/.local/bin:$HOME/.cargo/bin:$PATH
cd $QDEV_ROOT/Qiita
make build-common build-control-plane build-compute-orchestrator
cd $QDEV_ROOT && [ -f postgres_17.sif ] || apptainer pull postgres_17.sif docker://postgres:17
[ -f rust_1.91.sif ] || apptainer pull rust_1.91.sif docker://rust:1.91-bookworm
apptainer exec -B $QDEV_ROOT --env CARGO_HOME=$QDEV_ROOT/cargo-home,CARGO_BUILD_JOBS=32 rust_1.91.sif   bash -c "cd $QDEV_ROOT/Qiita/qiita-data-plane && cargo build --release --features duckdb/bundled"
ldd $QDEV_ROOT/Qiita/qiita-data-plane/target/release/qiita-data-plane | grep -E "not found|libstdc" || true
$QDEV_ROOT/Qiita/qiita-data-plane/target/release/qiita-data-plane --help 2>&1 | head -3 || true
echo BUILD-DONE
