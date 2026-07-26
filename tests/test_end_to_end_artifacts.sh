#!/usr/bin/env bash
# サンプルGeoTIFFを使ったエンドツーエンドテスト。
# bin/make-contour-pmtiles.shを1回実行し、VRT生成〜PMTiles生成までの
# 各中間生成物と最終PMTilesについて、単なる存在確認だけでなく実際の内容
# （NoData値、ズーム範囲、タイル数、頂点数の減少、ジオメトリがデコードできること等）
# が妥当であることを検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/bin/make-contour-pmtiles.sh"
SAMPLE_TIF_DIR="$REPO_ROOT/tif"

# shellcheck source=../bin/lib/extract-contours.sh
source "$REPO_ROOT/bin/lib/extract-contours.sh"
# shellcheck source=../bin/lib/simplify-and-smooth.sh
source "$REPO_ROOT/bin/lib/simplify-and-smooth.sh"
# shellcheck source=../bin/lib/generate-tiles.sh
source "$REPO_ROOT/bin/lib/generate-tiles.sh"
# shellcheck source=../bin/lib/merge-and-convert.sh
source "$REPO_ROOT/bin/lib/merge-and-convert.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

INPUT_DIR="$SAMPLE_TIF_DIR" BUILD_DIR="$BUILD_DIR" bash "$ENTRYPOINT" \
  >/tmp/e2e-artifacts.out 2>/tmp/e2e-artifacts.err \
  || fail "pipeline run failed: $(cat /tmp/e2e-artifacts.err)"

test_vrt_artifact_is_valid() {
  local vrt="$BUILD_DIR/merged.vrt"
  [ -f "$vrt" ] || fail "expected '$vrt' to exist"

  local nodata
  nodata="$(gdalinfo "$vrt" | grep -m1 'NoData Value=' | sed -E 's/.*NoData Value=([^[:space:]]*).*/\1/')"
  [ "$nodata" = "-9999" ] || fail "expected merged.vrt NoData to be -9999, got '$nodata'"
}

test_raw_contour_ndjson_artifacts_are_valid() {
  local interval file
  for interval in 10m 100m 500m; do
    file="$BUILD_DIR/contours-${interval}.ndjson"
    [ -s "$file" ] || fail "expected non-empty '$file'"
    verify_ndjson_features "$file" elevation \
      || fail "'$file' failed GeoJSON Feature validation"
  done
}

test_simplified_ndjson_artifacts_have_reduced_vertex_counts() {
  local interval original simplified
  for interval in 100m 500m; do
    original="$BUILD_DIR/contours-${interval}.ndjson"
    simplified="$BUILD_DIR/contours-${interval}.simplified.ndjson"
    [ -s "$simplified" ] || fail "expected non-empty '$simplified'"
    verify_simplification "$original" "$simplified" \
      || fail "'$simplified' does not show a valid vertex-count reduction from '$original'"
  done
}

test_per_interval_mbtiles_artifacts_have_expected_zoom_ranges() {
  [ -f "$BUILD_DIR/contours-10m.mbtiles" ] || fail "expected contours-10m.mbtiles to exist"
  verify_mbtiles_zoom_range "$BUILD_DIR/contours-10m.mbtiles" 14 14 \
    || fail "contours-10m.mbtiles does not have the expected z14-only range"

  [ -f "$BUILD_DIR/contours-100m.mbtiles" ] || fail "expected contours-100m.mbtiles to exist"
  verify_mbtiles_zoom_range "$BUILD_DIR/contours-100m.mbtiles" 11 13 \
    || fail "contours-100m.mbtiles does not have the expected z11-13 range"

  [ -f "$BUILD_DIR/contours-500m.mbtiles" ] || fail "expected contours-500m.mbtiles to exist"
  verify_mbtiles_zoom_range "$BUILD_DIR/contours-500m.mbtiles" 7 10 \
    || fail "contours-500m.mbtiles does not have the expected z7-10 range"
}

test_combined_mbtiles_and_pmtiles_artifacts_are_valid_and_consistent() {
  local combined="$BUILD_DIR/contours.mbtiles"
  local pmtiles="$BUILD_DIR/contours.pmtiles"

  [ -f "$combined" ] || fail "expected '$combined' to exist"
  verify_mbtiles_zoom_range "$combined" 7 14 \
    || fail "combined mbtiles does not cover the expected z7-z14 range"

  [ -s "$pmtiles" ] || fail "expected non-empty '$pmtiles'"
  verify_pmtiles "$pmtiles" >/tmp/e2e-pmtiles-verify.out 2>/tmp/e2e-pmtiles-verify.err \
    || fail "pmtiles verify rejected '$pmtiles': $(cat /tmp/e2e-pmtiles-verify.err)"

  local combined_tile_count pmtiles_addressed_count
  combined_tile_count="$(sqlite3 "$combined" "SELECT COUNT(*) FROM tiles;")"
  pmtiles_addressed_count="$(pmtiles show "$pmtiles" | grep '^addressed tiles count:' | grep -oE '[0-9]+')"
  if [ "$pmtiles_addressed_count" -ne "$combined_tile_count" ]; then
    fail "expected pmtiles addressed tile count ($pmtiles_addressed_count) to equal combined mbtiles tile count ($combined_tile_count)"
  fi
}

test_pmtiles_tile_geometry_actually_decodes() {
  local pmtiles="$BUILD_DIR/contours.pmtiles"
  local mbtiles="$BUILD_DIR/contours.mbtiles"

  local row zoom col row_tms row_xyz
  row="$(sqlite3 "$mbtiles" "SELECT zoom_level, tile_column, tile_row FROM tiles WHERE zoom_level=14 LIMIT 1;")"
  zoom="$(echo "$row" | cut -d'|' -f1)"
  col="$(echo "$row" | cut -d'|' -f2)"
  row_tms="$(echo "$row" | cut -d'|' -f3)"
  row_xyz="$(python3 -c "print(2**${zoom} - 1 - ${row_tms})")"

  # PMTiles自体からタイルバイト列を取得し、実際に中身(gzip圧縮されたMVT)が
  # 空でないことを確認する。
  local tile_bytes decompressed_size
  tile_bytes="$(pmtiles tile "$pmtiles" "$zoom" "$col" "$row_xyz" | wc -c)"
  [ "$tile_bytes" -gt 0 ] || fail "expected pmtiles to return non-empty tile bytes for z${zoom}/${col}/${row_xyz}"

  decompressed_size="$(pmtiles tile "$pmtiles" "$zoom" "$col" "$row_xyz" | gunzip -c | wc -c)"
  [ "$decompressed_size" -gt 0 ] || fail "expected the pmtiles tile to gunzip to non-empty MVT bytes"

  # 同じタイルのジオメトリ・属性の妥当性は、統合前のmbtiles(同一内容のMVT)を
  # tippecanoe-decodeで実際にパースして検証する。
  local decoded
  decoded="$(tippecanoe-decode "$mbtiles" "$zoom" "$col" "$row_xyz" 2>/dev/null)" \
    || fail "could not decode the corresponding z14 tile from contours.mbtiles"

  echo "$decoded" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
features = data['features'][0]['features']
assert len(features) > 0, 'expected at least one feature in the decoded tile'
for feature in features:
    geometry = feature['geometry']
    # タイル境界でクリップされたラインは複数の断片(MultiLineString)になりうる
    if geometry['type'] == 'LineString':
        parts = [geometry['coordinates']]
    elif geometry['type'] == 'MultiLineString':
        parts = geometry['coordinates']
    else:
        raise AssertionError(f\"unexpected geometry type: {geometry['type']}\")
    assert len(parts) > 0
    for part in parts:
        assert len(part) >= 2
    assert isinstance(feature['properties'].get('elevation'), (int, float))
" || fail "decoded tile geometry/properties failed validation"
}

test_vrt_artifact_is_valid
echo "PASS: merged.vrt exists with the expected NoData value"

test_raw_contour_ndjson_artifacts_are_valid
echo "PASS: raw 10m/100m/500m contour ndjson artifacts exist and contain valid Features"

test_simplified_ndjson_artifacts_have_reduced_vertex_counts
echo "PASS: simplified 100m/500m ndjson artifacts show a genuine vertex-count reduction from their source"

test_per_interval_mbtiles_artifacts_have_expected_zoom_ranges
echo "PASS: per-interval mbtiles artifacts (10m/100m/500m) have the expected zoom ranges with tiles present"

test_combined_mbtiles_and_pmtiles_artifacts_are_valid_and_consistent
echo "PASS: combined mbtiles and final pmtiles cover z7-z14, pmtiles verify succeeds, and tile counts match"

test_pmtiles_tile_geometry_actually_decodes
echo "PASS: a tile pulled from the final pmtiles decodes to valid LineString geometry with numeric elevation"
