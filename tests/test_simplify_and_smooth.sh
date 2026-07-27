#!/usr/bin/env bash
# bin/lib/simplify-and-smooth.sh (Visvalingam簡略化 → Chaikin平滑化 → Visvalingam簡略化)
# の動作を検証するテスト。
#
# 1. 意図的に角張った合成ラインに対して simplify_and_smooth を適用し、頂点数の減少・
#    角度の緩和（より鈍角になること）・始終点の座標保持を、具体的な座標値で検証する。
#    あわせて、Chaikin平滑化直後（後段のVisvalingam簡略化を適用する前）の中間状態と
#    比較し、後段簡略化が頂点数をさらに減らすこと、および簡略化・平滑化前の元の
#    入力と比べて最終出力でも角張りが緩和されたままであることを検証する。
# 2. 実サンプルGeoTIFFから抽出した実際の100m/500m間隔の等高線ndjsonに対して
#    simplify_and_smooth を適用し、頂点数が減少し自己交差が発生しないことを検証する。
# 3. パイプラインの10m間隔ndjsonが、このステップを経ても元データと完全に一致する
#    （簡略化・平滑化が適用されない）ことを検証する。

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

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- テスト1: 合成データによる頂点数減少・角度緩和・端点保持の検証 -----------------

make_angular_fixture() {
  # 直線区間に冗長な共線点を挟んだ、複数の直角コーナーを持つ折れ線を作る。
  # Visvalingamは直線区間の冗長点を間引きやすく、コーナー自体は保持しやすいため、
  # 「頂点数は減るがコーナーは残る」という簡略化の典型的な効きを確認できる。
  python3 - "$1" <<'PY'
import json
import sys


def segment_points(a, b, n):
    ax, ay = a
    bx, by = b
    return [[ax + (bx - ax) * i / n, ay + (by - ay) * i / n] for i in range(n + 1)]


corners = [[0, 0], [0, 10], [10, 10], [10, 20], [20, 20], [20, 30], [30, 30]]
coords = [corners[0]]
for i in range(len(corners) - 1):
    coords.extend(segment_points(corners[i], corners[i + 1], 10)[1:])

feature = {
    "type": "Feature",
    "properties": {"ID": 0, "elevation": 100},
    "geometry": {"type": "LineString", "coordinates": coords},
}

with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps(feature) + "\n")
PY
}

min_turn_angle() {
  python3 - "$REPO_ROOT/bin/lib" "$1" <<'PY'
import json
import sys

sys.path.insert(0, sys.argv[1])
import verify_simplification as vs

feature = vs.read_ndjson_features(sys.argv[2])[0]
print(vs.min_turn_angle_degrees(feature["geometry"]["coordinates"]))
PY
}

vertex_count_of() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    feature = json.loads(f.readline())
print(len(feature["geometry"]["coordinates"]))
PY
}

endpoints_of() {
  # 数値として比較するため、浮動小数点の表記ゆれ(30 vs 30.0)を吸収した正規形で出力する。
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    feature = json.loads(f.readline())
coords = feature["geometry"]["coordinates"]
print(json.dumps([[float(v) for v in coords[0]], [float(v) for v in coords[-1]]]))
PY
}

test_synthetic_angular_line_is_simplified_and_smoothed() {
  local fixture result chaikin_intermediate visvalingam_intermediate
  fixture="$TMP_DIR/angular.ndjson"
  result="$TMP_DIR/angular.result.ndjson"
  visvalingam_intermediate="$TMP_DIR/angular.visvalingam-intermediate.ndjson"
  chaikin_intermediate="$TMP_DIR/angular.chaikin-intermediate.ndjson"

  make_angular_fixture "$fixture"

  simplify_and_smooth "$fixture" "$result" "$SIMPLIFY_PERCENTAGE_100M" "$CHAIKIN_ITERATIONS" \
    || fail "simplify_and_smooth failed on the synthetic angular fixture"

  # simplify_and_smooth内部と同じ手順（簡略化→平滑化）を独立に再現し、後段の
  # 2回目Visvalingam簡略化を適用する前の中間状態（頂点数・角度）と比較できるようにする。
  mapshaper_simplify "$fixture" "$visvalingam_intermediate" "$SIMPLIFY_PERCENTAGE_100M" \
    || fail "setup: mapshaper_simplify failed while reproducing the pre-post-smooth-simplify intermediate"
  chaikin_smooth_ndjson "$visvalingam_intermediate" "$chaikin_intermediate" "$CHAIKIN_ITERATIONS" "$fixture" \
    || fail "setup: chaikin_smooth_ndjson failed while reproducing the pre-post-smooth-simplify intermediate"

  local orig_count chaikin_count new_count
  orig_count="$(vertex_count_of "$fixture")"
  chaikin_count="$(vertex_count_of "$chaikin_intermediate")"
  new_count="$(vertex_count_of "$result")"
  if [ "$new_count" -ge "$orig_count" ]; then
    fail "expected vertex count to decrease for the synthetic fixture (original=$orig_count, result=$new_count)"
  fi
  if [ "$new_count" -ge "$chaikin_count" ]; then
    fail "expected the post-smooth Visvalingam pass to further reduce vertex count below the Chaikin-only intermediate (chaikin-only=$chaikin_count, final=$new_count)"
  fi

  # 後段のVisvalingam簡略化は、頂点間の実効面積が小さい点を優先的に間引くため、
  # Chaikin平滑化直後の中間状態(chaikin_intermediate)と比べると最小角度が多少縮む
  # ことはある（コーナー近傍の点が間引かれるため。上で使うのは頂点数比較のみ）。
  # ここで検証すべきは、簡略化・平滑化前の元の角張った入力と比べて、後段簡略化を
  # 経た最終出力でも角張りが緩和されたままであること。
  local orig_angle new_angle
  orig_angle="$(min_turn_angle "$fixture")"
  new_angle="$(min_turn_angle "$result")"
  if ! python3 -c "import sys; sys.exit(0 if float('$new_angle') > float('$orig_angle') else 1)"; then
    fail "expected sharpest corner to remain less acute than the original even after the post-smooth simplify pass (original min angle=$orig_angle deg, final min angle=$new_angle deg)"
  fi

  local orig_endpoints new_endpoints
  orig_endpoints="$(endpoints_of "$fixture")"
  new_endpoints="$(endpoints_of "$result")"
  if [ "$orig_endpoints" != "$new_endpoints" ]; then
    fail "expected start/end coordinates to be preserved exactly (original=$orig_endpoints, result=$new_endpoints)"
  fi
}

# --- テスト2: 実サンプルデータでの頂点数減少・自己交差なしの検証 -------------------

test_real_sample_data_is_simplified_without_self_intersections() {
  local vrt contours_100m contours_500m result_100m result_500m
  vrt="$TMP_DIR/merged.vrt"
  contours_100m="$TMP_DIR/contours-100m.ndjson"
  contours_500m="$TMP_DIR/contours-500m.ndjson"
  result_100m="$TMP_DIR/contours-100m.simplified.ndjson"
  result_500m="$TMP_DIR/contours-500m.simplified.ndjson"

  build_vrt "$SAMPLE_TIF_DIR" "$vrt" >/dev/null 2>&1 || fail "setup: could not build sample VRT"
  extract_contours "$vrt" 100 "$contours_100m" >/dev/null 2>&1 || fail "setup: could not extract 100m contours"
  extract_contours "$vrt" 500 "$contours_500m" >/dev/null 2>&1 || fail "setup: could not extract 500m contours"

  simplify_and_smooth "$contours_100m" "$result_100m" "$SIMPLIFY_PERCENTAGE_100M" \
    || fail "simplify_and_smooth (and its internal verification) failed for real 100m sample data"
  simplify_and_smooth "$contours_500m" "$result_500m" "$SIMPLIFY_PERCENTAGE_500M" \
    || fail "simplify_and_smooth (and its internal verification) failed for real 500m sample data"

  # simplify_and_smooth内部でverify_simplificationが既に頂点数減少・自己交差なしを
  # 検証しているため、ここでは「非0終了しなかった」ことに加えて出力が空でないことを確認する。
  [ -s "$result_100m" ] || fail "expected non-empty simplified output for 100m interval"
  [ -s "$result_500m" ] || fail "expected non-empty simplified output for 500m interval"
}

# --- テスト3: 10m間隔ndjsonがこのステップを経ても元データと一致することの検証 -----

test_10m_interval_is_not_simplified_by_the_pipeline() {
  local build_dir
  build_dir="$TMP_DIR/pipeline-build"

  INPUT_DIR="$SAMPLE_TIF_DIR" BUILD_DIR="$build_dir" bash "$REPO_ROOT/bin/make-contour-pmtiles.sh" \
    >/tmp/simplify-pipeline.out 2>/tmp/simplify-pipeline.err \
    || fail "pipeline run failed: $(cat /tmp/simplify-pipeline.err)"

  local pipeline_10m independent_10m
  pipeline_10m="$build_dir/contours-10m.ndjson"
  independent_10m="$TMP_DIR/independent-contours-10m.ndjson"

  [ -f "$pipeline_10m" ] || fail "expected pipeline to produce '$pipeline_10m'"

  extract_contours "$build_dir/merged.vrt" 10 "$independent_10m" >/dev/null 2>&1 \
    || fail "setup: could not independently extract 10m contours for comparison"

  if ! diff -q "$pipeline_10m" "$independent_10m" >/dev/null 2>&1; then
    fail "expected pipeline's contours-10m.ndjson to be byte-identical to an unprocessed extraction (i.e. untouched by simplify/smooth)"
  fi
}

# --- テスト0: verify_simplification が実際に問題を検出できることの確認 -----------
# (簡略化前より頂点数が増えた「改悪」データを意図的に作り、拒否されることを確認する)

test_verify_simplification_rejects_vertex_count_increase() {
  local original bloated status
  original="$TMP_DIR/verify-original.ndjson"
  bloated="$TMP_DIR/verify-bloated.ndjson"

  python3 - "$original" "$bloated" <<'PY'
import json
import sys

original_path, bloated_path = sys.argv[1], sys.argv[2]

small = {
    "type": "Feature",
    "properties": {"ID": 0, "elevation": 100},
    "geometry": {"type": "LineString", "coordinates": [[0, 0], [1, 1], [2, 2]]},
}
bigger = {
    "type": "Feature",
    "properties": {"ID": 0, "elevation": 100},
    "geometry": {"type": "LineString", "coordinates": [[0, 0], [0.5, 0.5], [1, 1], [1.5, 1.5], [2, 2]]},
}

with open(original_path, "w", encoding="utf-8") as f:
    f.write(json.dumps(small) + "\n")
with open(bloated_path, "w", encoding="utf-8") as f:
    f.write(json.dumps(bigger) + "\n")
PY

  status=0
  verify_simplification "$original" "$bloated" >/tmp/verify-bloated.out 2>/tmp/verify-bloated.err || status=$?

  if [ "$status" -eq 0 ]; then
    fail "expected verify_simplification to reject output whose vertex count increased"
  fi

  grep -q "did not decrease" /tmp/verify-bloated.err \
    || fail "expected error to explain the vertex count did not decrease, got: $(cat /tmp/verify-bloated.err)"
}

test_verify_simplification_rejects_vertex_count_increase
echo "PASS: verify_simplification rejects output whose vertex count increased (not a rubber stamp)"

test_synthetic_angular_line_is_simplified_and_smoothed
echo "PASS: simplify_and_smooth reduces vertex count (further than the Chaikin-only intermediate), keeps the sharpest angle less acute than the original after the post-smooth simplify pass, and preserves endpoints on a synthetic fixture"

test_real_sample_data_is_simplified_without_self_intersections
echo "PASS: simplify_and_smooth succeeds (vertex count decreases, no self-intersections) on real 100m/500m sample data"

test_10m_interval_is_not_simplified_by_the_pipeline
echo "PASS: the pipeline leaves the 10m interval ndjson untouched by simplify/smooth"
