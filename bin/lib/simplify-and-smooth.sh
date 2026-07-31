#!/usr/bin/env bash
# 等高線ndjsonに対して Visvalingam簡略化（mapshaper） → Chaikin平滑化 の順で適用する。
# 10m間隔の等高線には適用しない（呼び出し側でこのステップをスキップする）。

set -euo pipefail

SIMPLIFY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# デフォルト値はサンプルデータ(tif/)で生成したPMTilesを確認して決定した。
# 100mより500mの方が低いズーム帯(z7-10)で使われるため、より強い簡略化(残す頂点の
# 割合を小さく)にしている。Chaikin反復回数は、合成した直角コーナーの折れ線で
# 検証した際に2回で90°の角を約153°まで緩和できており(tests/test_simplify_and_smooth.sh)、
# 意図した「角張らない滑らかな形状」を満たすため2とした。反復回数を増やすほど
# chaikin_smooth.pyの頂点数予算チェック(--budget-ndjson)で反復回数が自動的に
# 抑制される小さいラインが増えるため、むやみに増やしても効果が出にくい。
# 詳しい経緯はopenspec/changes/create-make-contour-mvt-tool/design.mdのDecisionsを参照。
#
# その後、国土地理院最適化ベクトルタイル(viewerでのスワイプ比較)を基準にこれらの値の
# 妥当性を再検証したが、この4つのデフォルト値を変更する根拠は見つからなかった
# (SIMPLIFY_PERCENTAGE_100M/500Mを大きく振ってもz11の等高線の密集具合はほとんど
# 変わらず、CHAIKIN_ITERATIONSを2から8まで増やしてもz10のレンダリングはピクセル単位で
# 不変だった)。Weighted Visvalingamはライン内の頂点を間引く処理でありライン本数自体は
# 減らせないため、密集は主に等高線間隔の選び方に起因し、Chaikinのコーナーカットは
# 1〜2反復でほぼ収束するため、それ以上反復しても地形データに実在する有意な折れは
# 丸めきれない。詳しい経緯はopenspec/changes/tune-simplify-smooth-percentages/
# baseline-comparison.md, 100m-band-tuning.md, 500m-band-tuning.mdを参照。
SIMPLIFY_PERCENTAGE_100M="${SIMPLIFY_PERCENTAGE_100M:-20%}"
SIMPLIFY_PERCENTAGE_500M="${SIMPLIFY_PERCENTAGE_500M:-8%}"
CHAIKIN_ITERATIONS="${CHAIKIN_ITERATIONS:-2}"

# Chaikin平滑化は反復ごとに頂点数をほぼ2倍にし、その大半は滑らかな曲線を折れ線近似
# するための冗長なほぼ共線点である。この冗長頂点を間引くため、Chaikin平滑化の直後に
# もう一段Visvalingam簡略化を適用する。25%は平滑化で作った丸みの大部分を保持したまま
# 頂点数を減らす保守的な値として選んだ（詳しい経緯はopenspec/changes/
# add-post-smooth-simplify/design.mdのDecisionsを参照）。国土地理院最適化ベクトルタイル
# との比較でも15%〜60%の範囲でレンダリング結果に有意差はなく、25%を変更する根拠は
# なかった（openspec/changes/tune-simplify-smooth-percentages/を参照）。
SIMPLIFY_PERCENTAGE_POST_SMOOTH="${SIMPLIFY_PERCENTAGE_POST_SMOOTH:-25%}"

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

# simplify_and_smooth <input_ndjson> <output_ndjson> <percentage> [iterations] [post_smooth_percentage]
# 簡略化（mapshaper Weighted Visvalingam）→平滑化（Chaikin）→簡略化（mapshaper
# Weighted Visvalingam、Chaikinで増えた冗長頂点の間引き）の順で適用し、結果を検証する。
simplify_and_smooth() {
  local input_ndjson="$1"
  local output_ndjson="$2"
  local percentage="$3"
  local iterations="${4:-$CHAIKIN_ITERATIONS}"
  local post_smooth_percentage="${5:-$SIMPLIFY_PERCENTAGE_POST_SMOOTH}"

  local tmp_simplified tmp_smoothed
  tmp_simplified="$(mktemp --suffix=.ndjson)"
  tmp_smoothed="$(mktemp --suffix=.ndjson)"

  mapshaper_simplify "$input_ndjson" "$tmp_simplified" "$percentage"
  chaikin_smooth_ndjson "$tmp_simplified" "$tmp_smoothed" "$iterations" "$input_ndjson"
  mapshaper_simplify "$tmp_smoothed" "$output_ndjson" "$post_smooth_percentage"
  rm -f "$tmp_simplified" "$tmp_smoothed"

  verify_simplification "$input_ndjson" "$output_ndjson"
}
