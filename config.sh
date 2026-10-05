# Site settings for the barnacle dev stack. Override any of these in the environment.
export QDEV_REPO=${QDEV_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
export QDEV_ROOT=${QDEV_ROOT:-/ddn_scratch/$USER/qiita-dev}
export QDEV_ACCOUNT=${QDEV_ACCOUNT:-}
export QDEV_EMAIL=${QDEV_EMAIL:-$USER@ucsd.edu}
