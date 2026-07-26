#!/usr/bin/env bash
# 標高DEM(GeoTIFF)群から等高線MVTを格納したPMTilesを生成するパイプラインのエントリーポイント。
#
# 各ステップの実処理は後続のIssueで実装される。現時点ではステップの呼び出し順序のみを
# 固定し、パイプライン全体の骨格を示す。
#
# 使い方:
#   bin/make-contour-pmtiles.sh
#
# 環境変数:
#   INPUT_DIR  入力GeoTIFFが置かれたディレクトリ (デフォルト: <repo>/tif)
#   BUILD_DIR  中間生成物・最終成果物の出力先ディレクトリ (デフォルト: <repo>/build)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=bin/lib/check-deps.sh
source "$SCRIPT_DIR/lib/check-deps.sh"
# shellcheck source=bin/lib/build-vrt.sh
source "$SCRIPT_DIR/lib/build-vrt.sh"
# shellcheck source=bin/lib/extract-contours.sh
source "$SCRIPT_DIR/lib/extract-contours.sh"

INPUT_DIR="${INPUT_DIR:-$REPO_ROOT/tif}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
MERGED_VRT="$BUILD_DIR/merged.vrt"
CONTOURS_10M_NDJSON="$BUILD_DIR/contours-10m.ndjson"
CONTOURS_100M_NDJSON="$BUILD_DIR/contours-100m.ndjson"
CONTOURS_500M_NDJSON="$BUILD_DIR/contours-500m.ndjson"

step_build_vrt() {
  echo "[1/6] VRT統合: $INPUT_DIR 配下のGeoTIFFを $MERGED_VRT に統合します"
  build_vrt "$INPUT_DIR" "$MERGED_VRT"
  verify_vrt_nodata "$MERGED_VRT" "$DEM_NODATA_VALUE"
  echo "[1/6] VRT統合: 完了（NoData=$DEM_NODATA_VALUE を確認）"
}

step_extract_contours() {
  echo "[2/6] 等高線抽出（ndjson生成）: 10m/100m/500m間隔でndjsonを生成します"

  extract_contours "$MERGED_VRT" 10 "$CONTOURS_10M_NDJSON"
  verify_ndjson_features "$CONTOURS_10M_NDJSON" elevation

  extract_contours "$MERGED_VRT" 100 "$CONTOURS_100M_NDJSON"
  verify_ndjson_features "$CONTOURS_100M_NDJSON" elevation

  extract_contours "$MERGED_VRT" 500 "$CONTOURS_500M_NDJSON"
  verify_ndjson_features "$CONTOURS_500M_NDJSON" elevation

  echo "[2/6] 等高線抽出（ndjson生成）: 完了（$CONTOURS_10M_NDJSON, $CONTOURS_100M_NDJSON, $CONTOURS_500M_NDJSON）"
}

step_simplify_and_smooth() {
  echo "[3/6] 簡略化・平滑化（Visvalingam + Chaikin）: 未実装（Issue #4で実装予定）"
}

step_generate_tiles() {
  echo "[4/6] ズームレベル別MVTタイル生成: 未実装（Issue #5で実装予定）"
}

step_merge_tiles() {
  echo "[5/6] MBTiles統合: 未実装（Issue #6で実装予定）"
}

step_convert_to_pmtiles() {
  echo "[6/6] PMTiles変換: 未実装（Issue #6で実装予定）"
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

  echo "パイプライン骨格の実行が完了しました（各ステップの実処理は今後のIssueで実装されます）"
}

main "$@"
