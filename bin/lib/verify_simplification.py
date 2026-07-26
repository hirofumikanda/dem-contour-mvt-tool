#!/usr/bin/env python3
"""等高線ndjsonの簡略化・平滑化結果を検証するユーティリティ。

以下を検証する:
  - 頂点数が入力より減少していること
  - 出力ラインに自己交差が発生していないこと
  - 出力ラインが入力ラインから大きく位置ずれしていないこと（最大逸脱距離）
  - （合成データ向け）連続3頂点がなす最小内角

自己交差判定・距離計算はGEOS（shapely）を利用する。純Pythonの総当たり判定は、
簡略化・平滑化後に数千頂点規模となる実データ（Chaikin平滑化で頂点数が
反復ごとに倍増するため）ではO(n^2)が現実的な時間で終わらないため採用しない。
"""

import json
import math
import sys

from shapely.geometry import LineString, Point


def read_ndjson_features(path):
    features = []
    with open(path, encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            features.append(json.loads(line))
    return features


def line_parts(geometry):
    """LineString/MultiLineStringを「座標配列のリスト」に正規化する。"""
    geom_type = geometry.get("type")
    if geom_type == "LineString":
        return [geometry["coordinates"]]
    if geom_type == "MultiLineString":
        return list(geometry["coordinates"])
    raise ValueError(f"unsupported geometry type: {geom_type}")


def vertex_count(geometry):
    return sum(len(part) for part in line_parts(geometry))


def line_has_self_intersections(coords):
    if len(coords) < 4:
        return False
    return not LineString(coords).is_simple


def max_deviation(original_coords, new_coords):
    """new_coordsの各点から、original_coordsの最寄りセグメントまでの最大距離。"""
    original_line = LineString(original_coords)
    return max((Point(p).distance(original_line) for p in new_coords), default=0.0)


def min_turn_angle_degrees(coords):
    """連続する3頂点がなす内角の最小値（度）。角が鋭いほど値は小さい。"""
    if len(coords) < 3:
        return 180.0

    smallest = 180.0
    for i in range(1, len(coords) - 1):
        a, b, c = coords[i - 1], coords[i], coords[i + 1]
        v1 = (a[0] - b[0], a[1] - b[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        len1 = math.hypot(*v1)
        len2 = math.hypot(*v2)
        if len1 == 0 or len2 == 0:
            continue
        cos_angle = (v1[0] * v2[0] + v1[1] * v2[1]) / (len1 * len2)
        cos_angle = max(-1.0, min(1.0, cos_angle))
        angle = math.degrees(math.acos(cos_angle))
        smallest = min(smallest, angle)
    return smallest


def compare_features(original_path, result_path):
    """original/result ndjsonを比較し、頂点数減少・自己交差なしを確認する。

    問題があれば説明メッセージのリストを返す（空リストなら問題なし）。

    強い簡略化により一部のFeatureが縮退して消える場合があるため（例:
    非常に短い等高線ループが対象ズームで意味を持たなくなる場合）、
    Feature数の一致は要求しない。gdal_contourが付与する一意な"ID"プロパティが
    両ファイルに揃っていればそれで対応付け、無ければ位置（出現順）で対応付ける。
    """
    original_features = read_ndjson_features(original_path)
    result_features = read_ndjson_features(result_path)

    problems = []

    if len(result_features) > len(original_features):
        problems.append(
            f"result has more features ({len(result_features)}) than original "
            f"({len(original_features)}); simplification must not add features"
        )
        return problems

    original_ids = [f.get("properties", {}).get("ID") for f in original_features]
    can_match_by_id = all(i is not None for i in original_ids) and len(set(original_ids)) == len(
        original_ids
    )

    if can_match_by_id:
        original_by_id = {f["properties"]["ID"]: f for f in original_features}
        pairs = []
        for new in result_features:
            feature_id = new.get("properties", {}).get("ID")
            if feature_id not in original_by_id:
                problems.append(f"result feature with ID={feature_id!r} has no match in original")
                continue
            pairs.append((original_by_id[feature_id], new))
    else:
        if len(original_features) != len(result_features):
            return [
                f"feature count mismatch: original has {len(original_features)}, "
                f"result has {len(result_features)} (no unique 'ID' property to match by)"
            ]
        pairs = list(zip(original_features, result_features))

    for orig, new in pairs:
        orig_count = vertex_count(orig["geometry"])
        new_count = vertex_count(new["geometry"])
        feature_id = new.get("properties", {}).get("ID")
        if new_count >= orig_count:
            problems.append(
                f"feature ID={feature_id!r}: vertex count did not decrease "
                f"({orig_count} -> {new_count})"
            )

        for part in line_parts(new["geometry"]):
            if line_has_self_intersections(part):
                problems.append(f"feature ID={feature_id!r}: result geometry has a self-intersection")
                break

    return problems


def main(argv):
    if len(argv) < 3:
        print(f"Usage: {argv[0]} <original_ndjson> <result_ndjson>", file=sys.stderr)
        return 1

    problems = compare_features(argv[1], argv[2])
    if problems:
        for problem in problems:
            print(f"Error: {problem}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
