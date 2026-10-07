#!/bin/bash
# One-time: write the three env files for the barnacle dev stack.
source "${QDEV_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/config.sh"
set -euo pipefail
B=$QDEV_ROOT; E=$B/env; Q=$B/Qiita
[ -f $E/control-plane.env ] && { echo "env files exist; refusing to overwrite"; exit 1; }
umask 077
PY=$Q/qiita-control-plane/.venv/bin/python
eval "$($PY -c "from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey as K; import base64; k=K.generate(); print('SIGNING=' + base64.b64encode(k.private_bytes_raw()).decode()); print('PUBLIC=' + base64.b64encode(k.public_key().public_bytes_raw()).decode())")"
COOKIE=$(openssl rand -base64 32); CPCO=$(openssl rand -base64 32)
PGPORT=55432; CP=18080; CO=18081; DP=15051
COMMON="PATH_SCRATCH=$B/scratch
MIINT_EXTENSION_DIRECTORY=$B/duckdb-ext
QIITA_ALLOW_TOKEN_ENV=true
CP_TO_CO_TOKEN=$CPCO
LOG_LEVEL=INFO"
cat > $E/control-plane.env <<X
DATABASE_URL=postgresql://$USER@localhost:$PGPORT/qiita
FLIGHT_TICKET_SIGNING_KEY=$SIGNING
LOGIN_COOKIE_SECRET_KEY=$COOKIE
PATH_INGEST_ROOTS=$B/scratch
CONTACT_EMAIL=$QDEV_EMAIL
COMPUTE_ORCHESTRATOR_URL=http://127.0.0.1:$CO
DATA_PLANE_URL=grpc://127.0.0.1:$DP
$COMMON
X
cat > $E/data-plane.env <<X
FLIGHT_TICKET_PUBLIC_KEY=$PUBLIC
DUCKLAKE_CATALOG_CONNSTR=dbname=qiita_ducklake host=localhost port=$PGPORT user=$USER
PATH_PERSISTENT=$B/persistent
LISTEN_ADDR=0.0.0.0:$DP
$COMMON
X
cat > $E/compute-orchestrator.env <<X
COMPUTE_BACKEND=local
QIITA_CP_URL=http://127.0.0.1:$CP
DATA_PLANE_URL=grpc://127.0.0.1:$DP
$COMMON
X
echo "PGPORT=$PGPORT CP=$CP CO=$CO DP=$DP" > $E/ports
ls -la $E
