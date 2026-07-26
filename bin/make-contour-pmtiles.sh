#!/usr/bin/env bash
# 標高DEM(GeoTIFF)群から等高線MVTを格納したPMTilesを生成するパイプラインのエントリーポイント。
#
# VRT統合 → 等高線抽出(ndjson) → 簡略化・平滑化 → MVTタイル生成 → MBTiles統合 →
# PMTiles変換、の6ステップを順に実行する。
#
# 使い方:
#   bin/make-contour-pmtiles.sh
#
# 環境変数:
#   INPUT_DIR               入力GeoTIFFが置かれたディレクトリ (デフォルト: <repo>/tif)
#   BUILD_DIR               中間生成物・最終成果物の出力先ディレクトリ (デフォルト: <repo>/build)
#   DEM_NODATA_VALUE        入力GeoTIFFのNoData値 (デフォルト: -9999)
#   CONTOUR_INTERVAL_10M    最高詳細帯の等高線間隔(m) (デフォルト: 10)
#   CONTOUR_INTERVAL_100M   中間帯の等高線間隔(m) (デフォルト: 100)
#   CONTOUR_INTERVAL_500M   広域帯の等高線間隔(m) (デフォルト: 500)
#   ZOOM_MIN_10M/ZOOM_MAX_10M     最高詳細帯のズーム範囲 (デフォルト: 14-14)
#   ZOOM_MIN_100M/ZOOM_MAX_100M   中間帯のズーム範囲 (デフォルト: 11-13)
#   ZOOM_MIN_500M/ZOOM_MAX_500M   広域帯のズーム範囲 (デフォルト: 7-10)
#   SIMPLIFY_PERCENTAGE_100M/500M  Visvalingam簡略化で保持する頂点の割合 (デフォルト: 20%/8%)
#   CHAIKIN_ITERATIONS       Chaikin平滑化の反復回数 (デフォルト: 2)
#   CONTOURS_LAYER_NAME       MVTのレイヤー名 (デフォルト: contours)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=bin/lib/check-deps.sh
source "$SCRIPT_DIR/lib/check-deps.sh"
# shellcheck source=bin/lib/build-vrt.sh
source "$SCRIPT_DIR/lib/build-vrt.sh"
# shellcheck source=bin/lib/extract-contours.sh
source "$SCRIPT_DIR/lib/extract-contours.sh"
# shellcheck source=bin/lib/simplify-and-smooth.sh
source "$SCRIPT_DIR/lib/simplify-and-smooth.sh"
# shellcheck source=bin/lib/generate-tiles.sh
source "$SCRIPT_DIR/lib/generate-tiles.sh"
# shellcheck source=bin/lib/merge-and-convert.sh
source "$SCRIPT_DIR/lib/merge-and-convert.sh"

INPUT_DIR="${INPUT_DIR:-$REPO_ROOT/tif}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"

CONTOUR_INTERVAL_10M="${CONTOUR_INTERVAL_10M:-10}"
CONTOUR_INTERVAL_100M="${CONTOUR_INTERVAL_100M:-100}"
CONTOUR_INTERVAL_500M="${CONTOUR_INTERVAL_500M:-500}"

ZOOM_MIN_10M="${ZOOM_MIN_10M:-14}"
ZOOM_MAX_10M="${ZOOM_MAX_10M:-14}"
ZOOM_MIN_100M="${ZOOM_MIN_100M:-11}"
ZOOM_MAX_100M="${ZOOM_MAX_100M:-13}"
ZOOM_MIN_500M="${ZOOM_MIN_500M:-7}"
ZOOM_MAX_500M="${ZOOM_MAX_500M:-10}"

MERGED_VRT="$BUILD_DIR/merged.vrt"
CONTOURS_10M_NDJSON="$BUILD_DIR/contours-10m.ndjson"
CONTOURS_100M_NDJSON="$BUILD_DIR/contours-100m.ndjson"
CONTOURS_500M_NDJSON="$BUILD_DIR/contours-500m.ndjson"
CONTOURS_100M_SIMPLIFIED_NDJSON="$BUILD_DIR/contours-100m.simplified.ndjson"
CONTOURS_500M_SIMPLIFIED_NDJSON="$BUILD_DIR/contours-500m.simplified.ndjson"
TILES_10M_MBTILES="$BUILD_DIR/contours-10m.mbtiles"
TILES_100M_MBTILES="$BUILD_DIR/contours-100m.mbtiles"
TILES_500M_MBTILES="$BUILD_DIR/contours-500m.mbtiles"
COMBINED_MBTILES="$BUILD_DIR/contours.mbtiles"
OUTPUT_PMTILES="$BUILD_DIR/contours.pmtiles"

step_build_vrt() {
  echo "[1/6] VRT統合: $INPUT_DIR 配下のGeoTIFFを $MERGED_VRT に統合します"
  build_vrt "$INPUT_DIR" "$MERGED_VRT"
  verify_vrt_nodata "$MERGED_VRT" "$DEM_NODATA_VALUE"
  echo "[1/6] VRT統合: 完了（NoData=$DEM_NODATA_VALUE を確認）"
}

step_extract_contours() {
  echo "[2/6] 等高線抽出（ndjson生成）: ${CONTOUR_INTERVAL_10M}m/${CONTOUR_INTERVAL_100M}m/${CONTOUR_INTERVAL_500M}m間隔でndjsonを生成します"

  extract_contours "$MERGED_VRT" "$CONTOUR_INTERVAL_10M" "$CONTOURS_10M_NDJSON"
  verify_ndjson_features "$CONTOURS_10M_NDJSON" elevation

  extract_contours "$MERGED_VRT" "$CONTOUR_INTERVAL_100M" "$CONTOURS_100M_NDJSON"
  verify_ndjson_features "$CONTOURS_100M_NDJSON" elevation

  extract_contours "$MERGED_VRT" "$CONTOUR_INTERVAL_500M" "$CONTOURS_500M_NDJSON"
  verify_ndjson_features "$CONTOURS_500M_NDJSON" elevation

  echo "[2/6] 等高線抽出（ndjson生成）: 完了（$CONTOURS_10M_NDJSON, $CONTOURS_100M_NDJSON, $CONTOURS_500M_NDJSON）"
}

step_simplify_and_smooth() {
  echo "[3/6] 簡略化・平滑化: ${CONTOUR_INTERVAL_100M}m/${CONTOUR_INTERVAL_500M}m間隔にVisvalingam簡略化+Chaikin平滑化を適用します（${CONTOUR_INTERVAL_10M}mは対象外）"

  simplify_and_smooth "$CONTOURS_100M_NDJSON" "$CONTOURS_100M_SIMPLIFIED_NDJSON" "$SIMPLIFY_PERCENTAGE_100M"
  simplify_and_smooth "$CONTOURS_500M_NDJSON" "$CONTOURS_500M_SIMPLIFIED_NDJSON" "$SIMPLIFY_PERCENTAGE_500M"

  echo "[3/6] 簡略化・平滑化: 完了（${CONTOUR_INTERVAL_10M}m間隔 $CONTOURS_10M_NDJSON は未加工のまま次段へ渡します）"
}

step_generate_tiles() {
  echo "[4/6] ズームレベル別MVTタイル生成: ${CONTOUR_INTERVAL_10M}m→z${ZOOM_MIN_10M}-${ZOOM_MAX_10M}, ${CONTOUR_INTERVAL_100M}m→z${ZOOM_MIN_100M}-${ZOOM_MAX_100M}, ${CONTOUR_INTERVAL_500M}m→z${ZOOM_MIN_500M}-${ZOOM_MAX_500M} でMBTilesを生成します"

  generate_tiles "$CONTOURS_10M_NDJSON" "$TILES_10M_MBTILES" "$ZOOM_MIN_10M" "$ZOOM_MAX_10M"
  verify_mbtiles_zoom_range "$TILES_10M_MBTILES" "$ZOOM_MIN_10M" "$ZOOM_MAX_10M"

  generate_tiles "$CONTOURS_100M_SIMPLIFIED_NDJSON" "$TILES_100M_MBTILES" "$ZOOM_MIN_100M" "$ZOOM_MAX_100M"
  verify_mbtiles_zoom_range "$TILES_100M_MBTILES" "$ZOOM_MIN_100M" "$ZOOM_MAX_100M"

  generate_tiles "$CONTOURS_500M_SIMPLIFIED_NDJSON" "$TILES_500M_MBTILES" "$ZOOM_MIN_500M" "$ZOOM_MAX_500M"
  verify_mbtiles_zoom_range "$TILES_500M_MBTILES" "$ZOOM_MIN_500M" "$ZOOM_MAX_500M"

  echo "[4/6] ズームレベル別MVTタイル生成: 完了（$TILES_10M_MBTILES, $TILES_100M_MBTILES, $TILES_500M_MBTILES）"
}

step_merge_tiles() {
  echo "[5/6] MBTiles統合: ${CONTOUR_INTERVAL_10M}m/${CONTOUR_INTERVAL_100M}m/${CONTOUR_INTERVAL_500M}m用MBTilesを1つに統合します"

  merge_mbtiles "$COMBINED_MBTILES" "$TILES_10M_MBTILES" "$TILES_100M_MBTILES" "$TILES_500M_MBTILES"
  verify_mbtiles_zoom_range "$COMBINED_MBTILES" "$ZOOM_MIN_500M" "$ZOOM_MAX_10M"

  echo "[5/6] MBTiles統合: 完了（$COMBINED_MBTILES, z${ZOOM_MIN_500M}-z${ZOOM_MAX_10M}）"
}

step_convert_to_pmtiles() {
  echo "[6/6] PMTiles変換: 統合MBTilesをPMTilesに変換します"

  convert_to_pmtiles "$COMBINED_MBTILES" "$OUTPUT_PMTILES"
  verify_pmtiles "$OUTPUT_PMTILES"

  echo "[6/6] PMTiles変換: 完了（$OUTPUT_PMTILES）"
}

main() {
  check_dependencies

  echo "入力ディレクトリ: $INPUT_DIR"
  echo "出力ディレクトリ: $BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  step_build_vrt
  step_extract_contours
  step_simplify_and_smooth
  step_generate_tiles
  step_merge_tiles
  step_convert_to_pmtiles

  echo "パイプラインの実行が完了しました: $OUTPUT_PMTILES"
}

main "$@"
