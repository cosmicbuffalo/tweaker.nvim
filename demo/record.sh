#!/usr/bin/env bash
# Repeatably record the tweaker.nvim feature-tour demo with VHS.
#
# Renders demo/demo.tape to demo/tweaker-demo.{gif,mp4}. Everything runs in an
# ISOLATED, ephemeral environment: the recorded Neovim uses demo/init.lua only
# (inkline + tweaker), and XDG_* point at a throwaway dir (/tmp/twd) that is
# wiped before and after the run — your real config, data, and overrides are
# never touched.
#
# Usage:  demo/record.sh
# Requires: vhs, ttyd, ffmpeg (VHS deps), nvim, git.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# vhs (via `go install`) and friends may live in the Go/Cargo bin dirs.
export PATH="$HOME/.cargo/bin:$HOME/go/bin:$PATH"

for bin in vhs ttyd ffmpeg nvim git; do
    command -v "$bin" >/dev/null || {
        echo "error: '$bin' not found on PATH" >&2
        exit 1
    }
done

# The demo needs the inkline colorscheme. Prefer a copy already installed by the
# user's plugin manager; otherwise clone it. Kept out of git (see .gitignore).
DEPS="$REPO_DIR/demo/.deps"
INK="$DEPS/inkline.nvim"
mkdir -p "$DEPS"
if [ ! -d "$INK" ]; then
    LAZY="$HOME/.local/share/nvim/lazy/inkline.nvim"
    if [ -d "$LAZY" ]; then
        echo "==> Using installed inkline.nvim ($LAZY)"
        cp -r "$LAZY" "$INK"
    else
        echo "==> Cloning inkline.nvim"
        git clone --depth 1 https://github.com/hectron/inkline.nvim "$INK"
    fi
fi

REC="/tmp/twd" # must match the XDG_* paths in demo/demo.tape
echo "==> Recording demo (drives a real TUI; do not touch the keyboard)"
rm -rf "$REC"
cd "$REPO_DIR"
vhs demo/demo.tape
rm -rf "$REC"

echo "==> Done. Wrote:"
ls -lh "$REPO_DIR"/demo/tweaker-demo.gif "$REPO_DIR"/demo/tweaker-demo.mp4 2>/dev/null || true
