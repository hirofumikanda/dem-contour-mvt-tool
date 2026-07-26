#!/usr/bin/env bash
# tests/配下のテストスクリプトを全て実行し、1つでも失敗すれば非0で終了する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  echo "== $(basename "$test_file") =="
  if ! bash "$test_file"; then
    failures=$((failures + 1))
  fi
  echo
done

if [ "$failures" -gt 0 ]; then
  echo "$failures test file(s) failed" >&2
  exit 1
fi

echo "All tests passed"
