#!/usr/bin/env python3
"""ndjson(GeoJSONSeq)のLineString/MultiLineStringにChaikinのコーナーカット平滑化を適用する。

始点・終点は各反復で固定し、コーナーカットで端点が動かないようにする。

Chaikinの1反復は頂点数をほぼ2倍にする（開いた折れ線の場合、n点はおよそ2n点になる）。
簡略化で強く間引かれた小さなライン（例: 局所的なピークを囲む短いループ）では、
固定の反復回数を適用すると簡略化前の頂点数を上回ってしまうことがある。
--budget-ndjson を指定すると、各Featureの反復回数を「簡略化前の頂点数を
下回る範囲で最大」になるよう自動的に抑制する。
"""

import argparse
import json
import sys


def chaikin_corner_cut(points, iterations):
    """開いた折れ線に対してChaikinのコーナーカットをiterations回適用する。

    各反復で、始点・終点は元の座標のまま残し、内部エッジは
    Q=0.75*p+0.25*q, R=0.25*p+0.75*q の2点に置き換える。
    """
    current = [list(p) for p in points]

    for _ in range(iterations):
        if len(current) < 3:
            break

        new_points = [current[0]]
        for i in range(len(current) - 1):
            p = current[i]
            q = current[i + 1]
            new_points.append([0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]])
            new_points.append([0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1]])
        new_points.append(current[-1])

        current = new_points

    return current


def smooth_geometry(geometry, iterations):
    geom_type = geometry.get("type")

    if geom_type == "LineString":
        geometry["coordinates"] = chaikin_corner_cut(geometry["coordinates"], iterations)
    elif geom_type == "MultiLineString":
        geometry["coordinates"] = [
            chaikin_corner_cut(line, iterations) for line in geometry["coordinates"]
        ]

    return geometry


def geometry_vertex_count(geometry):
    geom_type = geometry.get("type")
    if geom_type == "LineString":
        return len(geometry["coordinates"])
    if geom_type == "MultiLineString":
        return sum(len(part) for part in geometry["coordinates"])
    return 0


def predicted_vertex_count(current_count, iterations):
    """current_count頂点のラインにiterations回コーナーカットした後の頂点数を予測する。"""
    if current_count < 3:
        return current_count
    return current_count * (2 ** iterations)


def choose_iterations(current_count, budget, max_iterations):
    """budget（簡略化前の頂点数）を下回る範囲で最大の反復回数を選ぶ。

    どの反復回数でもbudgetを下回れない場合は0を返す（できる限り近づける）。
    """
    for iterations in range(max_iterations, -1, -1):
        if predicted_vertex_count(current_count, iterations) < budget:
            return iterations
    return 0


def read_ndjson(path):
    features = []
    with open(path, encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            features.append(json.loads(line))
    return features


def build_budget_lookup(budget_path):
    """budget_ndjsonから、Featureごとの頂点数を読み込む。

    gdal_contourが付与する一意な"ID"プロパティがあればそれで対応付け、
    無ければ出現順（位置）で対応付ける。戻り値は (lookup, by_id) で、
    by_id=Trueならlookupは {ID: 頂点数}、False なら [頂点数, ...] (位置対応)。
    """
    features = read_ndjson(budget_path)
    ids = [f.get("properties", {}).get("ID") for f in features]
    by_id = all(i is not None for i in ids) and len(set(ids)) == len(ids)

    if by_id:
        return {fid: geometry_vertex_count(f["geometry"]) for fid, f in zip(ids, features)}, True
    return [geometry_vertex_count(f["geometry"]) for f in features], False


def smooth_ndjson(input_path, output_path, max_iterations, budget_path=None):
    budget_lookup = None
    by_id = False
    if budget_path is not None:
        budget_lookup, by_id = build_budget_lookup(budget_path)

    features = read_ndjson(input_path)

    with open(output_path, "w", encoding="utf-8") as dst:
        for index, feature in enumerate(features):
            iterations = max_iterations

            if budget_lookup is not None:
                current_count = geometry_vertex_count(feature["geometry"])
                if by_id:
                    feature_id = feature.get("properties", {}).get("ID")
                    budget = budget_lookup.get(feature_id, current_count)
                else:
                    budget = budget_lookup[index] if index < len(budget_lookup) else current_count
                iterations = choose_iterations(current_count, budget, max_iterations)

            feature["geometry"] = smooth_geometry(feature["geometry"], iterations)
            dst.write(json.dumps(feature, separators=(",", ":")))
            dst.write("\n")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_ndjson")
    parser.add_argument("output_ndjson")
    parser.add_argument("iterations", type=int, nargs="?", default=2)
    parser.add_argument(
        "--budget-ndjson",
        default=None,
        help="この頂点数を下回るように、Featureごとに反復回数を自動的に抑制する",
    )
    return parser.parse_args(argv[1:])


def main(argv):
    args = parse_args(argv)
    smooth_ndjson(args.input_ndjson, args.output_ndjson, args.iterations, args.budget_ndjson)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
