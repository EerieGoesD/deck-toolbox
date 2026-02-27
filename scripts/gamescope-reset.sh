#!/usr/bin/env bash
set -euo pipefail
rm -rf "$HOME/.local/state/gamescope"
rm -rf "$HOME/.config/gamescope"
echo "Gamescope state/config cleared. Reboot recommended."
