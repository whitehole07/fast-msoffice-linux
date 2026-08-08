#!/usr/bin/env bash
# Full Windows desktop over RDP. Needed for setup tasks (installing Office,
# installing the add-in, Windows settings) before RemoteApp is wired up.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./env.sh
[ -x "$FREERDP_BIN" ] || die "FreeRDP missing. Run ./install.sh"
rdp_run "$@"
