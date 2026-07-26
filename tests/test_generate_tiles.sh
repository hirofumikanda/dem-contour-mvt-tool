#!/usr/bin/env bash
# bin/lib/generate-tiles.sh の動作を検証するテスト。
# - 実サンプルデータから生成した10m/100m/500m用のndjsonそれぞれに対しtippecanoeで
#   MBTilesを生成すると、metadataのminzoom/maxzoomが意図したズーム範囲と一致し、
#   その範囲内の全ズームレベルに実際にタイルが存在すること
# - --no-line-simplification により、tippecanoeが maxzoom であっても事前の
#   簡略化・平滑化結果の頂点を勝手に間引かないこと
# - verify_mbtiles_zoom_range が、実際にズーム範囲の不一致を検出できること
# を、実際にtippecanoe/sqlite3を実行して検証する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SAMPLE_TIF_DIR="$REPO_ROOT/tif"

# shellcheck source=../bin/lib/build-vrt.sh
source "$REPO_ROOT/bin/lib/build-vrt.sh"
# shellcheck source=../bin/lib/extract-contours.sh
source "$REPO_ROOT/bin/lib/extract-contours.sh"
# shellcheck source=../bin/lib/simplify-and-smooth.sh
source "$REPO_ROOT/bin/lib/simplify-and-smooth.sh"
# shellcheck source=../bin/lib/generate-tiles.sh
source "$REPO_ROOT/bin/lib/generate-tiles.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

metadata_value() {
  sqlite3 "$1" "SELECT value FROM metadata WHERE name='$2';"
}

tile_count_at_zoom() {
  sqlite3 "$1" "SELECT COUNT(*) FROM tiles WHERE zoom_level=$2;"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VRT="$TMP_DIR/merged.vrt"
CONTOURS_10M="$TMP_DIR/contours-10m.ndjson"
CONTOURS_100M="$TMP_DIR/contours-100m.ndjson"
CONTOURS_500M="$TMP_DIR/contours-500m.ndjson"
SIMPLIFIED_100M="$TMP_DIR/contours-100m.simplified.ndjson"
SIMPLIFIED_500M="$TMP_DIR/contours-500m.simplified.ndjson"

build_vrt "$SAMPLE_TIF_DIR" "$VRT" >/dev/null 2>&1 || fail "setup: could not build sample VRT"
extract_contours "$VRT" 10 "$CONTOURS_10M" >/dev/null 2>&1 || fail "setup: could not extract 10m contours"
extract_contours "$VRT" 100 "$CONTOURS_100M" >/dev/null 2>&1 || fail "setup: could not extract 100m contours"
extract_contours "$VRT" 500 "$CONTOURS_500M" >/dev/null 2>&1 || fail "setup: could not extract 500m contours"
simplify_and_smooth "$CONTOURS_100M" "$SIMPLIFIED_100M" "$SIMPLIFY_PERCENTAGE_100M" >/dev/null 2>&1 \
  || fail "setup: could not simplify+smooth 100m contours"
simplify_and_smooth "$CONTOURS_500M" "$SIMPLIFIED_500M" "$SIMPLIFY_PERCENTAGE_500M" >/dev/null 2>&1 \
  || fail "setup: could not simplify+smooth 500m contours"

test_10m_mbtiles_has_expected_zoom_range() {
  local mbtiles
  mbtiles="$TMP_DIR/contours-10m.mbtiles"

  generate_tiles "$CONTOURS_10M" "$mbtiles" 14 14 >/dev/null 2>&1 \
    || fail "generate_tiles failed for the 10m/z14 dataset"

  verify_mbtiles_zoom_range "$mbtiles" 14 14 \
    || fail "verify_mbtiles_zoom_range rejected a valid z14-only mbtiles"

  local minzoom maxzoom
  minzoom="$(metadata_value "$mbtiles" minzoom)"
  maxzoom="$(metadata_value "$mbtiles" maxzoom)"
  [ "$minzoom" = "14" ] || fail "expected minzoom=14, got $minzoom"
  [ "$maxzoom" = "14" ] || fail "expected maxzoom=14, got $maxzoom"

  local count
  count="$(tile_count_at_zoom "$mbtiles" 14)"
  [ "$count" -gt 0 ] || fail "expected at least one tile at zoom 14"
}

test_100m_mbtiles_has_expected_zoom_range() {
  local mbtiles
  mbtiles="$TMP_DIR/contours-100m.mbtiles"

  generate_tiles "$SIMPLIFIED_100M" "$mbtiles" 11 13 >/dev/null 2>&1 \
    || fail "generate_tiles failed for the 100m/z11-13 dataset"

  verify_mbtiles_zoom_range "$mbtiles" 11 13 \
    || fail "verify_mbtiles_zoom_range rejected a valid z11-13 mbtiles"

  local zoom count
  for zoom in 11 12 13; do
    count="$(tile_count_at_zoom "$mbtiles" "$zoom")"
    [ "$count" -gt 0 ] || fail "expected at least one tile at zoom $zoom in the 100m mbtiles"
  done
}

test_500m_mbtiles_has_expected_zoom_range() {
  local mbtiles
  mbtiles="$TMP_DIR/contours-500m.mbtiles"

  generate_tiles "$SIMPLIFIED_500M" "$mbtiles" 7 10 >/dev/null 2>&1 \
    || fail "generate_tiles failed for the 500m/z7-10 dataset"

  verify_mbtiles_zoom_range "$mbtiles" 7 10 \
    || fail "verify_mbtiles_zoom_range rejected a valid z7-10 mbtiles"

  local zoom count
  for zoom in 7 8 9 10; do
    count="$(tile_count_at_zoom "$mbtiles" "$zoom")"
    [ "$count" -gt 0 ] || fail "expected at least one tile at zoom $zoom in the 500m mbtiles"
  done
}

test_verify_mbtiles_zoom_range_rejects_wrong_range() {
  local mbtiles status
  mbtiles="$TMP_DIR/contours-10m-for-mismatch-check.mbtiles"
  generate_tiles "$CONTOURS_10M" "$mbtiles" 14 14 >/dev/null 2>&1 \
    || fail "setup: could not generate mbtiles for the mismatch check"

  status=0
  verify_mbtiles_zoom_range "$mbtiles" 7 10 >/tmp/verify-mbtiles-mismatch.out 2>/tmp/verify-mbtiles-mismatch.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected verify_mbtiles_zoom_range to reject a z14 mbtiles when checked against z7-10"
  fi
}

test_no_line_simplification_preserves_precomputed_vertices() {
  # 事前にVisvalingam+Chaikinで作った小さい(未クリップで収まる)ラインを選び、
  # tippecanoeが独自にさらに間引いていないことを、タイル内の頂点数が
  # ソースのndjsonと完全一致することで確認する。
  local mbtiles
  mbtiles="$TMP_DIR/contours-100m-precision-check.mbtiles"
  generate_tiles "$SIMPLIFIED_100M" "$mbtiles" 11 13 >/dev/null 2>&1 \
    || fail "setup: could not generate mbtiles for the precision check"

  python3 - "$SIMPLIFIED_100M" "$mbtiles" <<'PY' || fail "tippecanoe altered vertex count of a precomputed line at maxzoom"
import json
import math
import subprocess
import sys

ndjson_path, mbtiles_path = sys.argv[1], sys.argv[2]

candidate = None
with open(ndjson_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        feature = json.loads(line)
        coords = feature["geometry"]["coordinates"]
        if 5 <= len(coords) <= 30:
            candidate = feature
            break

if candidate is None:
    print("no suitable small feature found in sample data", file=sys.stderr)
    sys.exit(1)

lon, lat = candidate["geometry"]["coordinates"][0]
zoom = 13
n = 2 ** zoom
x = int((lon + 180.0) / 360.0 * n)
lat_rad = math.radians(lat)
y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)

decoded = subprocess.run(
    ["tippecanoe-decode", mbtiles_path, str(zoom), str(x), str(y)],
    capture_output=True,
    text=True,
    check=True,
)
tile = json.loads(decoded.stdout)
tile_features = tile["features"][0]["features"]

expected_id = candidate["properties"].get("ID")
match = next((f for f in tile_features if f["properties"].get("ID") == expected_id), None)
if match is None:
    print(f"feature ID={expected_id} not found in the decoded tile", file=sys.stderr)
    sys.exit(1)

expected_count = len(candidate["geometry"]["coordinates"])
actual_count = len(match["geometry"]["coordinates"])
if actual_count != expected_count:
    print(
        f"expected {expected_count} vertices for feature ID={expected_id}, "
        f"got {actual_count} after tiling",
        file=sys.stderr,
    )
    sys.exit(1)
PY
}

test_10m_mbtiles_has_expected_zoom_range
echo "PASS: 10m interval produces a z14-only mbtiles with tiles present"

test_100m_mbtiles_has_expected_zoom_range
echo "PASS: 100m interval produces a z11-13 mbtiles with tiles present at every zoom"

test_500m_mbtiles_has_expected_zoom_range
echo "PASS: 500m interval produces a z7-10 mbtiles with tiles present at every zoom"

test_verify_mbtiles_zoom_range_rejects_wrong_range
echo "PASS: verify_mbtiles_zoom_range rejects a zoom range mismatch (not a rubber stamp)"

test_no_line_simplification_preserves_precomputed_vertices
echo "PASS: --no-line-simplification preserves precomputed vertex counts at maxzoom"
