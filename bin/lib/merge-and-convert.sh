#!/usr/bin/env bash
# 間隔ごとのMBTilesを1つのMBTilesに統合し、さらにPMTilesへ変換する。

set -euo pipefail

MERGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bin/lib/generate-tiles.sh
source "$MERGE_LIB_DIR/generate-tiles.sh"

# merge_mbtiles <output_mbtiles> <input_mbtiles...>
# tile-joinで複数のMBTilesを1つに統合する。入力ごとにズーム範囲が異なる旨の
# 警告("mismatched maxzooms")が出ることがあるが、本パイプラインでは間隔ごとに
# 意図的にズーム範囲を分けているため無視してよい。
merge_mbtiles() {
  local output_mbtiles="$1"
  shift
  local input_mbtiles=("$@")

  if [ "${#input_mbtiles[@]}" -eq 0 ]; then
    echo "Error: merge_mbtiles requires at least one input mbtiles" >&2
    return 1
  fi

  local mbtiles
  for mbtiles in "${input_mbtiles[@]}"; do
    if [ ! -f "$mbtiles" ]; then
      echo "Error: input mbtiles '$mbtiles' does not exist" >&2
      return 1
    fi
  done

  mkdir -p "$(dirname "$output_mbtiles")"

  tile-join -f -o "$output_mbtiles" "${input_mbtiles[@]}"
}

# convert_to_pmtiles <input_mbtiles> <output_pmtiles>
convert_to_pmtiles() {
  local input_mbtiles="$1"
  local output_pmtiles="$2"

  if [ ! -f "$input_mbtiles" ]; then
    echo "Error: input mbtiles '$input_mbtiles' does not exist" >&2
    return 1
  fi

  mkdir -p "$(dirname "$output_pmtiles")"

  pmtiles convert "$input_mbtiles" "$output_pmtiles"
}

# verify_pmtiles <pmtiles_path>
# pmtiles verifyでアーカイブ構造が破損なく読み込めることを確認する。
verify_pmtiles() {
  local pmtiles_path="$1"

  if [ ! -f "$pmtiles_path" ]; then
    echo "Error: pmtiles file '$pmtiles_path' does not exist" >&2
    return 1
  fi

  pmtiles verify "$pmtiles_path"
}
