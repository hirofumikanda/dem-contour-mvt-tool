#!/usr/bin/env bash
# bin/make-contour-pmtiles.sh のエンドツーエンド動作を検証するテスト。
# - tif/配下のサンプルGeoTIFF(2ファイル)を入力にエントリーポイントを実行すると、
#   終了コード0で完了し、想定ファイル名のPMTilesが出力先に生成されること
# - 主要パラメータ（出力ディレクトリ、等高線間隔、ズーム範囲）を変更して再実行すると、
#   出力ファイルパスやズーム範囲がパラメータどおりに実際のMBTiles/PMTilesへ
#   反映されること
# を、実際にパイプライン全体を実行して検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/bin/make-contour-pmtiles.sh"
SAMPLE_TIF_DIR="$REPO_ROOT/tif"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

metadata_value() {
  sqlite3 "$1" "SELECT value FROM metadata WHERE name='$2';"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

test_default_run_produces_pmtiles_with_exit_zero() {
  local build_dir status
  build_dir="$TMP_DIR/default-build"

  status=0
  INPUT_DIR="$SAMPLE_TIF_DIR" BUILD_DIR="$build_dir" bash "$ENTRYPOINT" \
    >/tmp/pipeline-default.out 2>/tmp/pipeline-default.err || status=$?

  if [ "$status" -ne 0 ]; then
    fail "expected the entrypoint to exit 0 on sample data, got exit $status (stderr: $(cat /tmp/pipeline-default.err))"
  fi

  local pmtiles="$build_dir/contours.pmtiles"
  [ -f "$pmtiles" ] || fail "expected '$pmtiles' to be created"
  [ -s "$pmtiles" ] || fail "expected '$pmtiles' to be non-empty"

  pmtiles verify "$pmtiles" >/tmp/pipeline-default-verify.out 2>/tmp/pipeline-default-verify.err \
    || fail "pmtiles verify rejected the pipeline's output: $(cat /tmp/pipeline-default-verify.err)"

  local minzoom maxzoom
  minzoom="$(pmtiles show "$pmtiles" | grep '^min zoom:' | grep -oE '[0-9]+')"
  maxzoom="$(pmtiles show "$pmtiles" | grep '^max zoom:' | grep -oE '[0-9]+')"
  [ "$minzoom" = "7" ] || fail "expected default min zoom 7, got $minzoom"
  [ "$maxzoom" = "14" ] || fail "expected default max zoom 14, got $maxzoom"
}

test_custom_parameters_are_reflected_in_output() {
  local build_dir status
  build_dir="$TMP_DIR/custom-build"

  status=0
  INPUT_DIR="$SAMPLE_TIF_DIR" \
    BUILD_DIR="$build_dir" \
    ZOOM_MIN_10M=13 ZOOM_MAX_10M=13 \
    ZOOM_MIN_100M=9 ZOOM_MAX_100M=12 \
    ZOOM_MIN_500M=5 ZOOM_MAX_500M=8 \
    bash "$ENTRYPOINT" >/tmp/pipeline-custom.out 2>/tmp/pipeline-custom.err || status=$?

  if [ "$status" -ne 0 ]; then
    fail "expected the entrypoint to exit 0 with custom zoom parameters, got exit $status (stderr: $(cat /tmp/pipeline-custom.err))"
  fi

  # 出力ディレクトリがBUILD_DIRどおりに反映されていること
  [ -f "$build_dir/contours-10m.mbtiles" ] || fail "expected output under custom BUILD_DIR '$build_dir'"
  [ -f "$build_dir/contours.pmtiles" ] || fail "expected final pmtiles under custom BUILD_DIR '$build_dir'"

  # 各間隔のMBTilesが指定したズーム範囲どおりであること
  local minzoom maxzoom
  minzoom="$(metadata_value "$build_dir/contours-10m.mbtiles" minzoom)"
  maxzoom="$(metadata_value "$build_dir/contours-10m.mbtiles" maxzoom)"
  [ "$minzoom" = "13" ] && [ "$maxzoom" = "13" ] \
    || fail "expected 10m mbtiles zoom range 13-13, got ${minzoom}-${maxzoom}"

  minzoom="$(metadata_value "$build_dir/contours-100m.mbtiles" minzoom)"
  maxzoom="$(metadata_value "$build_dir/contours-100m.mbtiles" maxzoom)"
  [ "$minzoom" = "9" ] && [ "$maxzoom" = "12" ] \
    || fail "expected 100m mbtiles zoom range 9-12, got ${minzoom}-${maxzoom}"

  minzoom="$(metadata_value "$build_dir/contours-500m.mbtiles" minzoom)"
  maxzoom="$(metadata_value "$build_dir/contours-500m.mbtiles" maxzoom)"
  [ "$minzoom" = "5" ] && [ "$maxzoom" = "8" ] \
    || fail "expected 500m mbtiles zoom range 5-8, got ${minzoom}-${maxzoom}"

  # 統合MBTiles/PMTilesのズーム範囲も、指定した範囲の外周(5-13)に自動的に追従すること
  minzoom="$(metadata_value "$build_dir/contours.mbtiles" minzoom)"
  maxzoom="$(metadata_value "$build_dir/contours.mbtiles" maxzoom)"
  [ "$minzoom" = "5" ] && [ "$maxzoom" = "13" ] \
    || fail "expected combined mbtiles zoom range 5-13, got ${minzoom}-${maxzoom}"

  local pmtiles_minzoom pmtiles_maxzoom
  pmtiles_minzoom="$(pmtiles show "$build_dir/contours.pmtiles" | grep '^min zoom:' | grep -oE '[0-9]+')"
  pmtiles_maxzoom="$(pmtiles show "$build_dir/contours.pmtiles" | grep '^max zoom:' | grep -oE '[0-9]+')"
  [ "$pmtiles_minzoom" = "5" ] && [ "$pmtiles_maxzoom" = "13" ] \
    || fail "expected pmtiles zoom range 5-13, got ${pmtiles_minzoom}-${pmtiles_maxzoom}"
}

test_default_run_produces_pmtiles_with_exit_zero
echo "PASS: running the entrypoint on sample data exits 0 and produces a verified contours.pmtiles (z7-z14)"

test_custom_parameters_are_reflected_in_output
echo "PASS: overriding BUILD_DIR and zoom-range parameters is reflected in the actual output paths and MBTiles/PMTiles zoom metadata"
