#!/usr/bin/env bash
# 等高線ndjsonに対して Visvalingam簡略化（mapshaper） → Chaikin平滑化 の順で適用する。
# 10m間隔の等高線には適用しない（呼び出し側でこのステップをスキップする）。

set -euo pipefail

SIMPLIFY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIMPLIFY_PERCENTAGE_100M="${SIMPLIFY_PERCENTAGE_100M:-20%}"
SIMPLIFY_PERCENTAGE_500M="${SIMPLIFY_PERCENTAGE_500M:-8%}"
CHAIKIN_ITERATIONS="${CHAIKIN_ITERATIONS:-2}"

# mapshaper_simplify <input_ndjson> <output_ndjson> <percentage>
# mapshaperのWeighted Visvalingam簡略化を適用する。mapshaperはGeoJSON
# FeatureCollectionでしか書き出せないため、1行1FeatureのGeoJSONSeqへ変換して書き戻す。
mapshaper_simplify() {
  local input_ndjson="$1"
  local output_ndjson="$2"
  local percentage="$3"

  if [ ! -f "$input_ndjson" ]; then
    echo "Error: input ndjson '$input_ndjson' does not exist" >&2
    return 1
  fi

  local tmp_fc
  tmp_fc="$(mktemp --suffix=.json)"

  mapshaper -quiet -i "$input_ndjson" -simplify weighted "$percentage" -o format=geojson "$tmp_fc"

  python3 - "$tmp_fc" "$output_ndjson" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    data = json.load(f)

dropped = 0
with open(dst, "w", encoding="utf-8") as out:
    for feature in data["features"]:
        # 強い簡略化で頂点が2点未満に縮退したFeatureはmapshaperがgeometry:nullで
        # 返す。その対象ズームでは意味を持たない線として扱い、出力から除外する。
        if feature.get("geometry") is None:
            dropped += 1
            continue
        out.write(json.dumps(feature, separators=(",", ":")))
        out.write("\n")

if dropped:
    print(f"mapshaper_simplify: dropped {dropped} feature(s) collapsed by simplification", file=sys.stderr)
PY

  rm -f "$tmp_fc"
}

# chaikin_smooth_ndjson <input_ndjson> <output_ndjson> [iterations] [budget_ndjson]
# budget_ndjsonを指定すると、Chaikin平滑化でFeatureごとの頂点数がbudget_ndjson側の
# 頂点数を上回らないよう、反復回数をFeatureごとに自動的に抑制する。
chaikin_smooth_ndjson() {
  local input_ndjson="$1"
  local output_ndjson="$2"
  local iterations="${3:-$CHAIKIN_ITERATIONS}"
  local budget_ndjson="${4:-}"

  if [ -n "$budget_ndjson" ]; then
    python3 "$SIMPLIFY_LIB_DIR/chaikin_smooth.py" "$input_ndjson" "$output_ndjson" "$iterations" \
      --budget-ndjson "$budget_ndjson"
  else
    python3 "$SIMPLIFY_LIB_DIR/chaikin_smooth.py" "$input_ndjson" "$output_ndjson" "$iterations"
  fi
}

# verify_simplification <original_ndjson> <result_ndjson>
# 頂点数の減少・自己交差の不在をoriginal/result間で検証する。
verify_simplification() {
  local original_ndjson="$1"
  local result_ndjson="$2"

  python3 "$SIMPLIFY_LIB_DIR/verify_simplification.py" "$original_ndjson" "$result_ndjson"
}

# simplify_and_smooth <input_ndjson> <output_ndjson> <percentage> [iterations]
# 簡略化（mapshaper Weighted Visvalingam）→平滑化（Chaikin）の順で適用し、
# 結果を検証する。
simplify_and_smooth() {
  local input_ndjson="$1"
  local output_ndjson="$2"
  local percentage="$3"
  local iterations="${4:-$CHAIKIN_ITERATIONS}"

  local tmp_simplified
  tmp_simplified="$(mktemp --suffix=.ndjson)"

  mapshaper_simplify "$input_ndjson" "$tmp_simplified" "$percentage"
  chaikin_smooth_ndjson "$tmp_simplified" "$output_ndjson" "$iterations" "$input_ndjson"
  rm -f "$tmp_simplified"

  verify_simplification "$input_ndjson" "$output_ndjson"
}
