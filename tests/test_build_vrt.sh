#!/usr/bin/env bash
# bin/lib/build-vrt.sh の動作を検証するテスト。
# - tif/配下の実サンプルGeoTIFF(2ファイル)からVRTを生成すると、両ファイルの範囲を
#   合算した範囲になり、NoData値(-9999)が引き継がれること
# - 入力ディレクトリにGeoTIFFが1つも無い場合、エラーで失敗すること
# を、実際にgdalbuildvrt/gdalinfoを実行して検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_VRT_LIB="$REPO_ROOT/bin/lib/build-vrt.sh"
SAMPLE_TIF_DIR="$REPO_ROOT/tif"

# shellcheck source=../bin/lib/build-vrt.sh
source "$BUILD_VRT_LIB"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [ ! -d "$SAMPLE_TIF_DIR" ] || [ -z "$(find "$SAMPLE_TIF_DIR" -maxdepth 1 -iname '*.tif' -print -quit)" ]; then
  fail "setup: expected sample GeoTIFF files under '$SAMPLE_TIF_DIR'"
fi

test_build_vrt_merges_sample_geotiffs_with_nodata() {
  local tmp_dir output_vrt
  tmp_dir="$(mktemp -d)"
  output_vrt="$tmp_dir/merged.vrt"

  build_vrt "$SAMPLE_TIF_DIR" "$output_vrt" >/tmp/build-vrt.out 2>/tmp/build-vrt.err \
    || fail "build_vrt failed on sample data: $(cat /tmp/build-vrt.err)"

  [ -f "$output_vrt" ] || fail "expected VRT file '$output_vrt' to be created"

  verify_vrt_nodata "$output_vrt" "-9999" \
    || fail "verify_vrt_nodata rejected the VRT built from sample data"

  local info
  info="$(gdalinfo -json "$output_vrt")"

  python3 - "$info" <<'PY' || fail "merged VRT extent does not cover both sample GeoTIFFs"
import json
import sys

info = json.loads(sys.argv[1])
corners = info["cornerCoordinates"]
upper_left = corners["upperLeft"]
lower_right = corners["lowerRight"]

# 2枚のサンプルGeoTIFF(それぞれ経度0.125度幅)を東西に結合した範囲を期待する。
expected_upper_left = (138.0, 35.4166667)
expected_lower_right = (138.25, 35.3333333)

def close(a, b, tol=1e-6):
    return abs(a - b) < tol

ok = (
    close(upper_left[0], expected_upper_left[0])
    and close(upper_left[1], expected_upper_left[1])
    and close(lower_right[0], expected_lower_right[0])
    and close(lower_right[1], expected_lower_right[1])
)
sys.exit(0 if ok else 1)
PY

  rm -rf "$tmp_dir"
}

test_build_vrt_fails_on_empty_input_dir() {
  local empty_dir tmp_dir output_vrt status
  empty_dir="$(mktemp -d)"
  tmp_dir="$(mktemp -d)"
  output_vrt="$tmp_dir/merged.vrt"

  status=0
  build_vrt "$empty_dir" "$output_vrt" >/tmp/build-vrt-empty.out 2>/tmp/build-vrt-empty.err || status=$?

  rm -rf "$empty_dir" "$tmp_dir"

  if [ "$status" -eq 0 ]; then
    fail "expected build_vrt to fail when input directory has no GeoTIFF files"
  fi

  grep -q "no GeoTIFF" /tmp/build-vrt-empty.err \
    || fail "expected error message to explain no GeoTIFF files were found, got: $(cat /tmp/build-vrt-empty.err)"
}

test_build_vrt_merges_sample_geotiffs_with_nodata
echo "PASS: build_vrt merges sample GeoTIFFs into a VRT preserving NoData and combined extent"

test_build_vrt_fails_on_empty_input_dir
echo "PASS: build_vrt fails with a clear error when no GeoTIFF files are found"
