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

INPUT_DIR="${INPUT_DIR:-$REPO_ROOT/tif}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"

step_build_vrt() {
  echo "[1/6] VRT統合: 未実装（Issue #2で実装予定）"
}

step_extract_contours() {
  echo "[2/6] 等高線抽出（ndjson生成）: 未実装（Issue #3で実装予定）"
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
