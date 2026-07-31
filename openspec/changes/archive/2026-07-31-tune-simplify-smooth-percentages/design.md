## Context

`bin/lib/simplify-and-smooth.sh`の`simplify_and_smooth`は、100m/500m間隔の等高線ndjsonに対して次の3段階を固定の順序で適用する。

1. `mapshaper_simplify`（mapshaperのWeighted Visvalingam簡略化、保持する頂点割合は`SIMPLIFY_PERCENTAGE_100M`/`SIMPLIFY_PERCENTAGE_500M`）
2. `chaikin_smooth_ndjson`（Chaikinコーナーカット平滑化、反復回数は`CHAIKIN_ITERATIONS`）
3. `mapshaper_simplify`（Chaikinで増えた冗長頂点を間引く2回目のVisvalingam簡略化、保持割合は`SIMPLIFY_PERCENTAGE_POST_SMOOTH`）

`generate_tiles`（`bin/lib/generate-tiles.sh`）は`--no-line-simplification`でtippecanoeに渡すため、この3段階の出力形状がそのままズーム帯全体（100m→z11-13、500m→z7-10）でタイル化される。つまり同じ簡略化・平滑化済みジオメトリが、そのズーム帯の最も詳細なズーム（z13/z10）から最も広域なズーム（z11/z7）まで共通で使われる。

現在のデフォルト値（`SIMPLIFY_PERCENTAGE_100M=20%`, `SIMPLIFY_PERCENTAGE_500M=8%`, `CHAIKIN_ITERATIONS=2`, `SIMPLIFY_PERCENTAGE_POST_SMOOTH=25%`）は、`tif/`のサンプルデータで生成したPMTilesを単独で目視確認して決定されたもので（README「デフォルトパラメータの決定理由」）、国土地理院の等高線表現と比較して決定されたものではない。`add-contour-viewer`により、`viewer/`で自作PMTilesと国土地理院最適化ベクトルタイル（`std.json`、`viewer/src/styles/gsi_std.json`としてローカル複製済み）をスワイプ比較できる環境が既に整っている。

## Goals / Non-Goals

**Goals:**
- `viewer`のスワイプ比較を使い、z13以下（100m間隔のz11-13、500m間隔のz7-10）の自作等高線の形状を国土地理院最適化ベクトルタイルの等高線表現と見比べながら、4つのデフォルト値を調整する
- 調整後の値を`bin/lib/simplify-and-smooth.sh`・`bin/make-contour-pmtiles.sh`・READMEに反映し、既存の「デフォルトパラメータの決定理由」と同じ形式で決定根拠（国土地理院とどう比較して何を優先したか）を記録する
- 4段階処理の順序・関数インターフェース・10m間隔（z14）を簡略化しないという既存の制約は変更しない

**Non-Goals:**
- 国土地理院最適化ベクトルタイルとの自動的な形状差分計算（Hausdorff距離等の指標によるピクセル/頂点単位の定量比較ツール）の新規実装は行わない。国土地理院optimal_bvmapの生成アルゴリズム・簡略化基準は非公開であり、数値指標だけを頼りに最適化すると意味のない過学習になりかねないため、既存プロジェクトの慣例（README記載の目視確認による決定）を踏襲し、視覚的な近似を判断基準とする
- `simplify_and_smooth`の処理順序（Visvalingam→Chaikin→Visvalingam）やアルゴリズム自体の変更は行わない（`add-post-smooth-simplify`で決定済みの設計を踏襲する）
- 10m間隔（z14）のパラメータ・挙動は対象外（元々簡略化・平滑化を適用しない仕様のまま変更しない）
- `viewer`自体の機能追加・改修は行わない（既存のスワイプ比較機能をそのまま利用する）

## Decisions

### 1. 定量指標ではなく`viewer`での目視比較を判断基準にする
国土地理院optimal_bvmapの簡略化パラメータ・アルゴリズムは非公開であり、「頂点数」や「Hausdorff距離」のような単一指標だけでは、国土地理院の見た目に近づいているかを正しく評価できない（例えば頂点数を無理に近づけても曲線の滑らかさの印象が離れることがある）。既存のデフォルト値もREADMEの「デフォルトパラメータの決定理由」に記載の通り目視確認で決定されてきた。本変更でもこの慣例を踏襲し、`viewer`のスワイプ比較（`build/contours.pmtiles` vs `std.json`）を主たる判断基準とする。
- 代替案: 頂点数比やジオメトリ差分の定量スクリプトを新規作成 → 国土地理院側のアルゴリズムが不明なため数値目標の妥当性を説明できず、実装コストに見合わないため不採用。

### 2. 比較はズーム帯の両端（z11とz13、z7とz10）で行う
`--no-line-simplification`により、同一の簡略化済みジオメトリが100m帯（z11-13）・500m帯（z7-10）それぞれの全ズームで共通利用される。ズーム帯の最高detail側（z13, z10）では線が粗く見えやすく、最広域側（z11, z7）では逆に線が細かすぎて煩雑に見えやすいというトレードオフがあるため、両端で見比べて許容できるバランスの値を選ぶ。
- 代替案: 各帯の中間ズームのみで比較 → 両端での見え方の違いを見落とし、実運用時の粗さ/煩雑さのどちらかが許容範囲外になるリスクがあるため不採用。

### 3. 4パラメータは実データでの反復調整（trial-and-error）で決定し、決定理由をREADMEに追記する
`SIMPLIFY_PERCENTAGE_100M`/`SIMPLIFY_PERCENTAGE_500M`（1回目のVisvalingam）、`CHAIKIN_ITERATIONS`（Chaikin反復回数）、`SIMPLIFY_PERCENTAGE_POST_SMOOTH`（2回目のVisvalingam）は独立した環境変数だが、最終形状への影響は相互に依存する（例: Chaikin反復を増やすと頂点が増え、2回目のVisvalingamがより強く効く）。個別に最適化するのではなく、`bin/make-contour-pmtiles.sh`を実行し直しながら4値の組み合わせを反復調整し、`viewer`で確認した上で最終値を確定する。確定後、既存のREADME「デフォルトパラメータの決定理由」の記述形式に倣い、国土地理院との比較で何を優先して各値を選んだかを追記する。

## Risks / Trade-offs

- [国土地理院最適化ベクトルタイルの配信が一時的に利用できない場合、`viewer`での比較ができず調整作業が止まる] → READMEに記載済みの複製元（`gsi-cyberjapan/optimal_bvmap`の`std.json`）を使い、`std.json`自体はローカル複製済みのためスタイル定義は参照可能。タイル本体の配信障害時は別日に比較を再実施する。
- [目視確認は主観的で、確認者によって「近似できている」の判断基準がぶれる] → README決定理由に、どのズーム・どの地物（例: 急峻な地形の等高線、緩やかな地形の等高線）を見てどう判断したかを具体的に記録し、後から検証可能にする。
- [サンプルデータ（`tif/`配下）のみでの調整のため、他地域の地形（例えば海岸線に近い平地や複雑な尾根筋）では最適でない可能性がある] → 既存のデフォルト値決定と同じ制約であり、本変更のスコープ外。将来的に別データセットで再検証する運用は変更しない。

## Migration Plan

- 環境変数のデフォルト値のみの変更であり、後方互換性は保たれる（`SIMPLIFY_PERCENTAGE_*`等を明示指定しているユーザーには影響しない）
- ロールバックは`bin/lib/simplify-and-smooth.sh`のデフォルト値を元に戻すのみで完結する

## Open Questions

- なし（既存の3段階処理の順序・関数インターフェースは変更せず、デフォルト値のみを調整するスコープのため）
