#!/usr/bin/env bash
# 複数のGeoTIFF標高DEMを1つのVRTに統合する。
# NoData値を明示的に指定し、統合後のVRTでも同じNoData値が有効であることを検証する関数も提供する。

set -euo pipefail

DEM_NODATA_VALUE="${DEM_NODATA_VALUE:--9999}"

# build_vrt <input_dir> <output_vrt>
# input_dir配下の*.tifをすべて集めてgdalbuildvrtでoutput_vrtに統合する。
build_vrt() {
  local input_dir="$1"
  local output_vrt="$2"

  if [ ! -d "$input_dir" ]; then
    echo "Error: input directory '$input_dir' does not exist" >&2
    return 1
  fi

  local tif_files=()
  while IFS= read -r -d '' f; do
    tif_files+=("$f")
  done < <(find "$input_dir" -maxdepth 1 -type f -iname '*.tif' -print0 | sort -z)

  if [ "${#tif_files[@]}" -eq 0 ]; then
    echo "Error: no GeoTIFF (*.tif) files found in '$input_dir'" >&2
    return 1
  fi

  mkdir -p "$(dirname "$output_vrt")"

  gdalbuildvrt \
    -srcnodata "$DEM_NODATA_VALUE" \
    -vrtnodata "$DEM_NODATA_VALUE" \
    "$output_vrt" \
    "${tif_files[@]}"
}

# verify_vrt_nodata <vrt_path> <expected_nodata>
# gdalinfoの出力からNoData値を読み取り、期待値と一致するかを確認する。
verify_vrt_nodata() {
  local vrt_path="$1"
  local expected_nodata="$2"

  if [ ! -f "$vrt_path" ]; then
    echo "Error: VRT file '$vrt_path' does not exist" >&2
    return 1
  fi

  local actual_nodata
  actual_nodata="$(gdalinfo "$vrt_path" | grep -m1 'NoData Value=' | sed -E 's/.*NoData Value=([^[:space:]]*).*/\1/')"

  if [ -z "$actual_nodata" ]; then
    echo "Error: could not determine NoData value from '$vrt_path'" >&2
    return 1
  fi

  if ! python3 -c "import sys; sys.exit(0 if float('$actual_nodata') == float('$expected_nodata') else 1)" 2>/dev/null; then
    echo "Error: VRT NoData value '$actual_nodata' does not match expected '$expected_nodata'" >&2
    return 1
  fi

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_dir> <output_vrt>" >&2
    exit 1
  fi
  build_vrt "$1" "$2"
  verify_vrt_nodata "$2" "$DEM_NODATA_VALUE"
fi
