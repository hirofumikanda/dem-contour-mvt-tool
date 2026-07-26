#!/usr/bin/env bash
# 異常系入力に対してパイプラインが適切にエラーまたは空成果物を扱うことを検証するテスト。
# gdal_createで小さな合成GeoTIFFをその場で作り、以下のケースを確認する:
#  - NoDataのみのGeoTIFF: 等高線抽出は成功するが結果は空になり、検証ステップが
#    明確なエラーメッセージとともに失敗する（サイレントに壊れたPMTilesを作らない）
#  - 標高が完全に一定(等高線が1本も引けない)なGeoTIFF: 同上
#  - 範囲が重ならない複数のGeoTIFF: gdalbuildvrt/gdal_contourがクラッシュせず、
#    ギャップを挟んだ有効なVRT・等高線を正常に生成できる（成功が適切な挙動）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SAMPLE_TIF_DIR="$REPO_ROOT/tif"

# shellcheck source=../bin/lib/build-vrt.sh
source "$REPO_ROOT/bin/lib/build-vrt.sh"
# shellcheck source=../bin/lib/extract-contours.sh
source "$REPO_ROOT/bin/lib/extract-contours.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_synthetic_geotiff() {
  # make_synthetic_geotiff <output_tif> <ulx> <uly> <lrx> <lry> <burn_value>
  local output="$1" ulx="$2" uly="$3" lrx="$4" lry="$5" burn_value="$6"

  gdal_create -q \
    -of GTiff -outsize 10 10 -bands 1 -ot Float64 \
    -a_srs EPSG:4326 -a_ullr "$ulx" "$uly" "$lrx" "$lry" \
    -a_nodata "$DEM_NODATA_VALUE" -burn "$burn_value" \
    "$output"
}

test_nodata_only_geotiff_yields_clear_error_not_silent_failure() {
  local input_dir vrt ndjson status
  input_dir="$TMP_DIR/nodata-only"
  mkdir -p "$input_dir"
  make_synthetic_geotiff "$input_dir/nodata.tif" 138.0 35.42 138.01 35.41 "$DEM_NODATA_VALUE"

  vrt="$TMP_DIR/nodata.vrt"
  ndjson="$TMP_DIR/nodata-contours.ndjson"

  build_vrt "$input_dir" "$vrt" >/dev/null 2>&1 || fail "expected build_vrt to succeed on a NoData-only GeoTIFF"

  extract_contours "$vrt" 10 "$ndjson" >/dev/null 2>&1 \
    || fail "expected extract_contours to succeed (producing an empty result) on a NoData-only VRT"
  [ -f "$ndjson" ] || fail "expected an ndjson file to be created even if empty"
  [ ! -s "$ndjson" ] || fail "expected the ndjson from a NoData-only GeoTIFF to be empty"

  status=0
  verify_ndjson_features "$ndjson" elevation >/tmp/error-nodata.out 2>/tmp/error-nodata.err || status=$?
  if [ "$status" -eq 0 ]; then
    fail "expected verify_ndjson_features to reject an empty contour result rather than silently accept it"
  fi
  grep -q "no Features" /tmp/error-nodata.err \
    || fail "expected a clear error message naming the problem, got: $(cat /tmp/error-nodata.err)"
}

test_flat_elevation_geotiff_yields_no_contours_and_clear_error() {
  local input_dir vrt ndjson status
  input_dir="$TMP_DIR/flat"
  mkdir -p "$input_dir"
  # 10/100/500いずれの間隔の倍数でもない標高にして、境界の丸めに左右されず
  # 確実に等高線が1本も生成されないようにする。
  make_synthetic_geotiff "$input_dir/flat.tif" 138.0 35.42 138.01 35.41 137.42

  vrt="$TMP_DIR/flat.vrt"
  ndjson="$TMP_DIR/flat-contours.ndjson"

  build_vrt "$input_dir" "$vrt" >/dev/null 2>&1 || fail "expected build_vrt to succeed on a flat-elevation GeoTIFF"

  extract_contours "$vrt" 10 "$ndjson" >/dev/null 2>&1 \
    || fail "expected extract_contours to succeed (producing an empty result) on a flat-elevation VRT"
  [ ! -s "$ndjson" ] || fail "expected the ndjson from a flat-elevation GeoTIFF to be empty (no contour crossings)"

  status=0
  verify_ndjson_features "$ndjson" elevation >/tmp/error-flat.out 2>/tmp/error-flat.err || status=$?
  if [ "$status" -eq 0 ]; then
    fail "expected verify_ndjson_features to reject an empty contour result rather than silently accept it"
  fi
}

test_non_overlapping_geotiffs_are_handled_gracefully() {
  local input_dir vrt ndjson
  input_dir="$TMP_DIR/non-overlapping"
  mkdir -p "$input_dir"

  # 実サンプルデータから20x20ピクセルの窓を切り出し、地理的に大きく離れた
  # 座標へ再配置することで、標高に本物の起伏を保ったまま範囲が重ならない
  # 2枚のGeoTIFFを作る。
  gdal_translate -q -srcwin 0 0 20 20 -a_ullr 138.0 35.416667 138.002222 35.414444 \
    "$SAMPLE_TIF_DIR/FG-GML-5338-00-dem10b-20161001.tif" "$input_dir/near.tif" \
    || fail "setup: could not create the first non-overlapping fixture"
  gdal_translate -q -srcwin 0 0 20 20 -a_ullr 140.0 36.416667 140.002222 36.414444 \
    "$SAMPLE_TIF_DIR/FG-GML-5338-00-dem10b-20161001.tif" "$input_dir/far.tif" \
    || fail "setup: could not create the second non-overlapping fixture"

  vrt="$TMP_DIR/non-overlapping.vrt"
  ndjson="$TMP_DIR/non-overlapping-contours.ndjson"

  build_vrt "$input_dir" "$vrt" >/tmp/error-gap-vrt.out 2>/tmp/error-gap-vrt.err \
    || fail "expected build_vrt to succeed on non-overlapping GeoTIFFs: $(cat /tmp/error-gap-vrt.err)"

  extract_contours "$vrt" 10 "$ndjson" >/tmp/error-gap-extract.out 2>/tmp/error-gap-extract.err \
    || fail "expected extract_contours to succeed on the gapped VRT: $(cat /tmp/error-gap-extract.err)"

  verify_ndjson_features "$ndjson" elevation \
    || fail "expected non-overlapping GeoTIFFs (each with real elevation variation) to still produce valid contours"
}

test_nodata_only_geotiff_yields_clear_error_not_silent_failure
echo "PASS: a NoData-only GeoTIFF produces an empty contour result and a clear, explicit verification error (no silent failure)"

test_flat_elevation_geotiff_yields_no_contours_and_clear_error
echo "PASS: a flat-elevation GeoTIFF (no contour crossings) produces an empty result and a clear, explicit verification error"

test_non_overlapping_geotiffs_are_handled_gracefully
echo "PASS: non-overlapping GeoTIFFs (large gap between them) are handled gracefully, producing valid contours without crashing"
