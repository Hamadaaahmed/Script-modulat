#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != "" ]; then
  export DOMAIN="$1"
fi
# Phase 2.5 runtime bridge: safe/idempotent deployment before service installer work.
python3 scripts/hamada-runtime-deploy deploy --source "$(pwd)" --root /opt/hamada
bash install/install.sh "$@"
