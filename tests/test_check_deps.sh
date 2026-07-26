#!/usr/bin/env bash
# bin/lib/check-deps.sh の動作を検証するテスト。
# - 全ての依存コマンドが揃っている場合に成功すること
# - 依存コマンドが1つでも欠けている場合に、そのコマンド名を含むエラーメッセージとともに
#   非0で終了すること
# を実際にPATHを操作して確認する（意味のないtrue===trueのようなアサーションは行わない）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_DEPS="$REPO_ROOT/bin/lib/check-deps.sh"
BASH_BIN="$(command -v bash)"

REQUIRED_COMMANDS=(gdalbuildvrt gdal_contour mapshaper tippecanoe tile-join pmtiles python3 sqlite3)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 全依存コマンドへのシンボリックリンクだけを含むPATHを作り、実行環境の実PATHに依存せず
# 「何が見えているか」を完全に制御する。
build_fake_path_dir() {
  local exclude="$1"
  local dir
  dir="$(mktemp -d)"
  local cmd real_path
  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if [ "$cmd" = "$exclude" ]; then
      continue
    fi
    real_path="$(command -v "$cmd")" || fail "setup: '$cmd' is not available in the current environment; cannot build test fixture"
    ln -s "$real_path" "$dir/$cmd"
  done
  echo "$dir"
}

test_success_when_all_dependencies_present() {
  local fake_path_dir
  fake_path_dir="$(build_fake_path_dir "")"

  if PATH="$fake_path_dir" "$BASH_BIN" "$CHECK_DEPS" >/tmp/check-deps.out 2>/tmp/check-deps.err; then
    rm -rf "$fake_path_dir"
    return 0
  else
    local status=$?
    rm -rf "$fake_path_dir"
    fail "expected check-deps.sh to exit 0 when all dependencies are present, got exit $status (stderr: $(cat /tmp/check-deps.err))"
  fi
}

test_failure_when_a_dependency_is_missing() {
  local missing_cmd="tippecanoe"
  local fake_path_dir
  fake_path_dir="$(build_fake_path_dir "$missing_cmd")"

  local status=0
  PATH="$fake_path_dir" "$BASH_BIN" "$CHECK_DEPS" >/tmp/check-deps.out 2>/tmp/check-deps.err || status=$?
  rm -rf "$fake_path_dir"

  if [ "$status" -eq 0 ]; then
    fail "expected check-deps.sh to fail when '$missing_cmd' is missing from PATH, but it exited 0"
  fi

  if ! grep -q "$missing_cmd" /tmp/check-deps.err; then
    fail "expected error output to mention missing command '$missing_cmd', got: $(cat /tmp/check-deps.err)"
  fi
}

test_success_when_all_dependencies_present
echo "PASS: check_dependencies succeeds when every required command is on PATH"

test_failure_when_a_dependency_is_missing
echo "PASS: check_dependencies fails with a message naming the missing command"
