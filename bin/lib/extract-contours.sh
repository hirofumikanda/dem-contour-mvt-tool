#!/usr/bin/env bash
# 統合VRTから指定間隔の等高線をndjson（改行区切りGeoJSON、GeoJSONSeq）として抽出する。

set -euo pipefail

DEM_NODATA_VALUE="${DEM_NODATA_VALUE:--9999}"

# extract_contours <vrt_path> <interval_meters> <output_ndjson>
# vrt_pathから interval_meters おきの等高線を抽出し、output_ndjsonにGeoJSONSeq形式で書き出す。
# 各Featureには標高値のプロパティ "elevation" が付与される。
extract_contours() {
  local vrt_path="$1"
  local interval="$2"
  local output_ndjson="$3"

  if [ ! -f "$vrt_path" ]; then
    echo "Error: VRT file '$vrt_path' does not exist" >&2
    return 1
  fi

  mkdir -p "$(dirname "$output_ndjson")"

  gdal_contour \
    -f GeoJSONSeq \
    -i "$interval" \
    -a elevation \
    -snodata "$DEM_NODATA_VALUE" \
    "$vrt_path" \
    "$output_ndjson"
}

# verify_ndjson_features <ndjson_path> <elevation_property>
# ndjsonの各行が有効なGeoJSON Featureとしてパースでき、指定した標高値プロパティを
# 数値として持つことを確認する。
verify_ndjson_features() {
  local ndjson_path="$1"
  local elevation_property="${2:-elevation}"

  if [ ! -f "$ndjson_path" ]; then
    echo "Error: ndjson file '$ndjson_path' does not exist" >&2
    return 1
  fi

  python3 - "$ndjson_path" "$elevation_property" <<'PY'
import json
import sys

path, elevation_property = sys.argv[1], sys.argv[2]

feature_count = 0
with open(path, encoding="utf-8") as f:
    for line_number, raw_line in enumerate(f, start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            feature = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"Error: line {line_number} is not valid JSON: {exc}", file=sys.stderr)
            sys.exit(1)

        if feature.get("type") != "Feature":
            print(f"Error: line {line_number} is not a GeoJSON Feature", file=sys.stderr)
            sys.exit(1)

        properties = feature.get("properties") or {}
        if elevation_property not in properties:
            print(
                f"Error: line {line_number} is missing property '{elevation_property}'",
                file=sys.stderr,
            )
            sys.exit(1)

        if not isinstance(properties[elevation_property], (int, float)):
            print(
                f"Error: line {line_number} property '{elevation_property}' is not numeric",
                file=sys.stderr,
            )
            sys.exit(1)

        feature_count += 1

if feature_count == 0:
    print(f"Error: '{path}' contains no Features", file=sys.stderr)
    sys.exit(1)
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <vrt_path> <interval_meters> <output_ndjson>" >&2
    exit 1
  fi
  extract_contours "$1" "$2" "$3"
  verify_ndjson_features "$3" elevation
fi
