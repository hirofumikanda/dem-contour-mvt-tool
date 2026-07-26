#!/usr/bin/env bash
# bin/make-contour-pmtiles.sh の骨格を検証するテスト。
# 各ステップ（VRT統合・等高線抽出・簡略化平滑化・タイル生成・MBTiles統合・PMTiles変換）の
# プレースホルダが「正しい順序」で呼び出され、スクリプトが構文エラーなく最後まで到達し
# 終了コード0で完了することを、実際の標準出力の内容と順序で確認する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/bin/make-contour-pmtiles.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

TMP_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_BUILD_DIR"' EXIT

status=0
BUILD_DIR="$TMP_BUILD_DIR" bash "$ENTRYPOINT" >/tmp/entrypoint.out 2>/tmp/entrypoint.err || status=$?

if [ "$status" -ne 0 ]; then
  fail "expected entrypoint skeleton to exit 0, got exit $status (stderr: $(cat /tmp/entrypoint.err))"
fi

expected_order=(
  "\[1/6\] VRT統合"
  "\[2/6\] 等高線抽出"
  "\[3/6\] 簡略化・平滑化"
  "\[4/6\] ズームレベル別MVTタイル生成"
  "\[5/6\] MBTiles統合"
  "\[6/6\] PMTiles変換"
)

last_line_number=0
for pattern in "${expected_order[@]}"; do
  line_number="$(grep -n -m1 -E "$pattern" /tmp/entrypoint.out | cut -d: -f1 || true)"
  if [ -z "$line_number" ]; then
    fail "expected output to contain a line matching '$pattern', got: $(cat /tmp/entrypoint.out)"
  fi
  if [ "$line_number" -le "$last_line_number" ]; then
    fail "expected step matching '$pattern' to appear after the previous step, but it appeared out of order"
  fi
  last_line_number="$line_number"
done

if [ ! -d "$TMP_BUILD_DIR" ]; then
  fail "expected BUILD_DIR '$TMP_BUILD_DIR' to be created by the entrypoint"
fi

echo "PASS: entrypoint skeleton runs all six step placeholders in order and exits 0"
