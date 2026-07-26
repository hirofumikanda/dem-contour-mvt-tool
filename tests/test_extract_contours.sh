#!/usr/bin/env bash
# bin/lib/extract-contours.sh の動作を検証するテスト。
# - 実サンプルVRT(tif/配下のGeoTIFFから統合)に対して10m/100m/500m間隔の等高線ndjsonを
#   生成すると、各ファイルの全行が有効なGeoJSON Featureとしてパースでき、数値の標高値
#   プロパティを持つこと
# - 間隔が小さいほど生成されるFeature数が多いこと（10m > 100m > 500m）
# - 存在しないVRTを指定した場合にエラーで失敗すること
# を、実際にgdal_contourを実行して検証する。

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

count_features() {
  local path="$1"
  grep -cve '^[[:space:]]*$' "$path"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SAMPLE_VRT="$TMP_DIR/merged.vrt"
build_vrt "$SAMPLE_TIF_DIR" "$SAMPLE_VRT" >/dev/null 2>&1 \
  || fail "setup: could not build sample VRT from '$SAMPLE_TIF_DIR'"

test_extract_contours_produces_valid_ndjson_at_each_interval() {
  local interval output
  for interval in 10 100 500; do
    output="$TMP_DIR/contours-${interval}m.ndjson"
    extract_contours "$SAMPLE_VRT" "$interval" "$output" >/tmp/extract-contours.out 2>/tmp/extract-contours.err \
      || fail "extract_contours failed for interval=${interval}m: $(cat /tmp/extract-contours.err)"

    [ -s "$output" ] || fail "expected non-empty ndjson output for interval=${interval}m"

    verify_ndjson_features "$output" elevation \
      || fail "verify_ndjson_features rejected valid ndjson output for interval=${interval}m"
  done
}

test_smaller_interval_yields_more_features() {
  local count_10m count_100m count_500m
  count_10m="$(count_features "$TMP_DIR/contours-10m.ndjson")"
  count_100m="$(count_features "$TMP_DIR/contours-100m.ndjson")"
  count_500m="$(count_features "$TMP_DIR/contours-500m.ndjson")"

  if [ "$count_10m" -le "$count_100m" ]; then
    fail "expected 10m interval ($count_10m features) to yield more contours than 100m interval ($count_100m features)"
  fi

  if [ "$count_100m" -le "$count_500m" ]; then
    fail "expected 100m interval ($count_100m features) to yield more contours than 500m interval ($count_500m features)"
  fi
}

test_verify_ndjson_features_rejects_malformed_input() {
  local bad_ndjson status
  bad_ndjson="$TMP_DIR/bad.ndjson"
  printf '%s\n' '{"type": "Feature", "properties": {}, "geometry": null}' > "$bad_ndjson"

  status=0
  verify_ndjson_features "$bad_ndjson" elevation >/tmp/verify-bad.out 2>/tmp/verify-bad.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected verify_ndjson_features to fail when the elevation property is missing"
  fi

  grep -q "elevation" /tmp/verify-bad.err \
    || fail "expected error to mention the missing 'elevation' property, got: $(cat /tmp/verify-bad.err)"
}

test_extract_contours_fails_on_missing_vrt() {
  local missing_vrt status
  missing_vrt="$TMP_DIR/does-not-exist.vrt"

  status=0
  extract_contours "$missing_vrt" 10 "$TMP_DIR/should-not-exist.ndjson" >/tmp/extract-missing.out 2>/tmp/extract-missing.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected extract_contours to fail when the VRT does not exist"
  fi
}

test_extract_contours_produces_valid_ndjson_at_each_interval
echo "PASS: extract_contours produces valid GeoJSONSeq ndjson with numeric elevation at 10m/100m/500m"

test_smaller_interval_yields_more_features
echo "PASS: smaller contour intervals yield strictly more features (10m > 100m > 500m)"

test_verify_ndjson_features_rejects_malformed_input
echo "PASS: verify_ndjson_features rejects a Feature missing the elevation property"

test_extract_contours_fails_on_missing_vrt
echo "PASS: extract_contours fails when the input VRT does not exist"
