#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# d_rocket — CI helper
# ─────────────────────────────────────────────────────────────────────────────
#
# Mirrors the structure of the legacy `tool/ci.sh` in the monorepo root
# (which fans out to all sub-packages). This file is scoped to the
# d_rocket package only and is safe to run in isolation.
#
# Usage:
#   ./tool/ci.sh pub        # dart pub get
#   ./tool/ci.sh analyze    # dart analyze
#   ./tool/ci.sh test       # dart test
#   ./tool/ci.sh all        # pub + analyze + test
#
# On macOS arm64 with Dart 3.11+ the AOT snapshot compilation step of
# `build_runner` is known to fail with a `SocketException: Broken pipe`
# (dart-lang/sdk#56601). Until upstream fixes it, run build_runner
# invocations with `--force-jit` to skip AOT and surface the real
# (logical) error.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR/.."

cmd="${1:-all}"

case "$cmd" in
  pub)
    dart pub get
    ;;
  analyze)
    dart analyze
    ;;
  test)
    dart test
    ;;
  all)
    dart pub get
    dart analyze
    dart test
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Usage: $0 {pub|analyze|test|all}" >&2
    exit 2
    ;;
esac
