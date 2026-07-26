#!/usr/bin/env bash
# bin/lib/merge-and-convert.sh の動作を検証するテスト。
# - z7-10用/z11-13用/z14用の3つのMBTilesをtile-joinで統合すると、z7からz14までの
#   各ズームレベルのタイルを含む単一のMBTilesになること
# - 統合済みMBTilesをPMTilesに変換すると、統合MBTilesと同じズーム範囲・タイル数を
#   持つ単一のPMTilesになり、pmtiles verifyが破損なく成功すること
# を、実サンプルデータから生成したMBTilesを使って実際にtile-join/pmtilesを実行して検証する。

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
# shellcheck source=../bin/lib/merge-and-convert.sh
source "$REPO_ROOT/bin/lib/merge-and-convert.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tile_count() {
  sqlite3 "$1" "SELECT COUNT(*) FROM tiles;"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VRT="$TMP_DIR/merged.vrt"
CONTOURS_10M="$TMP_DIR/contours-10m.ndjson"
CONTOURS_100M="$TMP_DIR/contours-100m.ndjson"
CONTOURS_500M="$TMP_DIR/contours-500m.ndjson"
SIMPLIFIED_100M="$TMP_DIR/contours-100m.simplified.ndjson"
SIMPLIFIED_500M="$TMP_DIR/contours-500m.simplified.ndjson"
MBTILES_10M="$TMP_DIR/contours-10m.mbtiles"
MBTILES_100M="$TMP_DIR/contours-100m.mbtiles"
MBTILES_500M="$TMP_DIR/contours-500m.mbtiles"

build_vrt "$SAMPLE_TIF_DIR" "$VRT" >/dev/null 2>&1 || fail "setup: could not build sample VRT"
extract_contours "$VRT" 10 "$CONTOURS_10M" >/dev/null 2>&1 || fail "setup: could not extract 10m contours"
extract_contours "$VRT" 100 "$CONTOURS_100M" >/dev/null 2>&1 || fail "setup: could not extract 100m contours"
extract_contours "$VRT" 500 "$CONTOURS_500M" >/dev/null 2>&1 || fail "setup: could not extract 500m contours"
simplify_and_smooth "$CONTOURS_100M" "$SIMPLIFIED_100M" "$SIMPLIFY_PERCENTAGE_100M" >/dev/null 2>&1 \
  || fail "setup: could not simplify+smooth 100m contours"
simplify_and_smooth "$CONTOURS_500M" "$SIMPLIFIED_500M" "$SIMPLIFY_PERCENTAGE_500M" >/dev/null 2>&1 \
  || fail "setup: could not simplify+smooth 500m contours"
generate_tiles "$CONTOURS_10M" "$MBTILES_10M" 14 14 >/dev/null 2>&1 || fail "setup: could not generate 10m mbtiles"
generate_tiles "$SIMPLIFIED_100M" "$MBTILES_100M" 11 13 >/dev/null 2>&1 || fail "setup: could not generate 100m mbtiles"
generate_tiles "$SIMPLIFIED_500M" "$MBTILES_500M" 7 10 >/dev/null 2>&1 || fail "setup: could not generate 500m mbtiles"

test_merge_mbtiles_covers_full_zoom_range() {
  local combined
  combined="$TMP_DIR/combined.mbtiles"

  merge_mbtiles "$combined" "$MBTILES_10M" "$MBTILES_100M" "$MBTILES_500M" >/dev/null 2>&1 \
    || fail "merge_mbtiles failed to merge the three interval mbtiles"

  verify_mbtiles_zoom_range "$combined" 7 14 \
    || fail "merged mbtiles does not cover the expected z7-z14 range"

  local zoom count
  for zoom in 7 8 9 10 11 12 13 14; do
    count="$(sqlite3 "$combined" "SELECT COUNT(*) FROM tiles WHERE zoom_level=${zoom};")"
    [ "$count" -gt 0 ] || fail "expected merged mbtiles to have tiles at zoom $zoom"
  done

  local total_before total_after
  total_before="$(( $(tile_count "$MBTILES_10M") + $(tile_count "$MBTILES_100M") + $(tile_count "$MBTILES_500M") ))"
  total_after="$(tile_count "$combined")"
  if [ "$total_after" -ne "$total_before" ]; then
    fail "expected merged tile count ($total_after) to equal the sum of inputs ($total_before) since zoom ranges do not overlap"
  fi
}

test_merge_mbtiles_fails_on_missing_input() {
  local status
  status=0
  merge_mbtiles "$TMP_DIR/should-not-exist.mbtiles" "$TMP_DIR/does-not-exist.mbtiles" \
    >/tmp/merge-missing.out 2>/tmp/merge-missing.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected merge_mbtiles to fail when an input mbtiles does not exist"
  fi
}

test_convert_to_pmtiles_matches_source_and_verifies() {
  local combined pmtiles
  combined="$TMP_DIR/combined-for-convert.mbtiles"
  pmtiles="$TMP_DIR/output.pmtiles"

  merge_mbtiles "$combined" "$MBTILES_10M" "$MBTILES_100M" "$MBTILES_500M" >/dev/null 2>&1 \
    || fail "setup: could not build combined mbtiles for the convert test"

  convert_to_pmtiles "$combined" "$pmtiles" >/tmp/convert.out 2>/tmp/convert.err \
    || fail "convert_to_pmtiles failed: $(cat /tmp/convert.err)"

  [ -s "$pmtiles" ] || fail "expected a non-empty pmtiles file to be created"

  verify_pmtiles "$pmtiles" >/tmp/pmtiles-verify.out 2>/tmp/pmtiles-verify.err \
    || fail "pmtiles verify rejected the converted archive: $(cat /tmp/pmtiles-verify.err)"

  local show_output
  show_output="$(pmtiles show "$pmtiles")"

  echo "$show_output" | grep -q "^min zoom: 7$" \
    || fail "expected pmtiles min zoom to be 7, got: $show_output"
  echo "$show_output" | grep -q "^max zoom: 14$" \
    || fail "expected pmtiles max zoom to be 14, got: $show_output"

  local combined_tile_count pmtiles_addressed_count
  combined_tile_count="$(tile_count "$combined")"
  pmtiles_addressed_count="$(echo "$show_output" | grep "^addressed tiles count:" | grep -oE '[0-9]+')"
  if [ "$pmtiles_addressed_count" -ne "$combined_tile_count" ]; then
    fail "expected pmtiles addressed tile count ($pmtiles_addressed_count) to equal the source mbtiles tile count ($combined_tile_count)"
  fi
}

test_verify_pmtiles_fails_on_corrupted_file() {
  local corrupted status
  corrupted="$TMP_DIR/corrupted.pmtiles"
  printf 'not a real pmtiles archive' > "$corrupted"

  status=0
  verify_pmtiles "$corrupted" >/tmp/verify-corrupted.out 2>/tmp/verify-corrupted.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected verify_pmtiles to fail on a corrupted/non-pmtiles file"
  fi
}

test_merge_mbtiles_covers_full_zoom_range
echo "PASS: merge_mbtiles combines the three interval mbtiles into a single z7-z14 archive"

test_merge_mbtiles_fails_on_missing_input
echo "PASS: merge_mbtiles fails when an input mbtiles does not exist"

test_convert_to_pmtiles_matches_source_and_verifies
echo "PASS: convert_to_pmtiles produces a pmtiles matching the source mbtiles zoom range/tile count, and it passes pmtiles verify"

test_verify_pmtiles_fails_on_corrupted_file
echo "PASS: verify_pmtiles rejects a corrupted/non-pmtiles file (not a rubber stamp)"
