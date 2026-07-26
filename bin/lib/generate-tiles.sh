#!/usr/bin/env bash
# 等高線ndjsonから、指定したズーム範囲のMVTをtippecanoeでMBTilesとして生成する。

set -euo pipefail

CONTOURS_LAYER_NAME="${CONTOURS_LAYER_NAME:-contours}"

# generate_tiles <input_ndjson> <output_mbtiles> <min_zoom> <max_zoom>
# 事前にVisvalingam簡略化・Chaikin平滑化を済ませたラインの形状をtippecanoe側で
# さらに簡略化させないよう --no-line-simplification を指定する
# (指定しない場合、maxzoomであっても頂点が間引かれ、事前の簡略化・平滑化結果が
#  意図せず劣化することを実データで確認したため)。
generate_tiles() {
  local input_ndjson="$1"
  local output_mbtiles="$2"
  local min_zoom="$3"
  local max_zoom="$4"

  if [ ! -f "$input_ndjson" ]; then
    echo "Error: input ndjson '$input_ndjson' does not exist" >&2
    return 1
  fi

  mkdir -p "$(dirname "$output_mbtiles")"

  tippecanoe \
    --force \
    --output "$output_mbtiles" \
    --minimum-zoom "$min_zoom" \
    --maximum-zoom "$max_zoom" \
    --layer "$CONTOURS_LAYER_NAME" \
    --name "${CONTOURS_LAYER_NAME} z${min_zoom}-z${max_zoom}" \
    --no-line-simplification \
    --no-progress-indicator \
    "$input_ndjson"
}

# verify_mbtiles_zoom_range <mbtiles_path> <expected_min_zoom> <expected_max_zoom>
# metadataのminzoom/maxzoomが期待どおりであること、かつ範囲内の全ズームに
# 実際にタイルが存在することを確認する。
verify_mbtiles_zoom_range() {
  local mbtiles_path="$1"
  local expected_min="$2"
  local expected_max="$3"

  if [ ! -f "$mbtiles_path" ]; then
    echo "Error: mbtiles file '$mbtiles_path' does not exist" >&2
    return 1
  fi

  local actual_min actual_max
  actual_min="$(sqlite3 "$mbtiles_path" "SELECT value FROM metadata WHERE name='minzoom';")"
  actual_max="$(sqlite3 "$mbtiles_path" "SELECT value FROM metadata WHERE name='maxzoom';")"

  if [ "$actual_min" != "$expected_min" ] || [ "$actual_max" != "$expected_max" ]; then
    echo "Error: '$mbtiles_path' has zoom range ${actual_min}-${actual_max}, expected ${expected_min}-${expected_max}" >&2
    return 1
  fi

  local zoom tile_count
  for zoom in $(seq "$expected_min" "$expected_max"); do
    tile_count="$(sqlite3 "$mbtiles_path" "SELECT COUNT(*) FROM tiles WHERE zoom_level=${zoom};")"
    if [ "$tile_count" -eq 0 ]; then
      echo "Error: '$mbtiles_path' has no tiles at zoom level ${zoom}" >&2
      return 1
    fi
  done

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <input_ndjson> <output_mbtiles> <min_zoom> <max_zoom>" >&2
    exit 1
  fi
  generate_tiles "$1" "$2" "$3" "$4"
  verify_mbtiles_zoom_range "$2" "$3" "$4"
fi
