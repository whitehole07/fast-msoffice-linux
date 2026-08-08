#!/usr/bin/env bash
# Excel as a native window on this desktop.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
# APP_NAME is what appears in alt-tab and the taskbar.
APP_NAME='Excel' exec ./rdp-app.sh 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE' "$@"
