## Why

Chaikinのコーナーカット平滑化は反復のたびに頂点数をほぼ2倍にする（`bin/lib/chaikin_smooth.py`のdocstring参照）。デフォルトの2反復では平滑化前の約4倍の頂点数になり、そのうち多くは滑らかな曲線を近似するために追加された、ほぼ共線な冗長点である。現状のパイプライン（`bin/lib/simplify-and-smooth.sh`の`simplify_and_smooth`）はVisvalingam簡略化→Chaikin平滑化の順で処理を終えており、この平滑化由来の頂点膨張を後段で間引く処理がない。100m・500m間隔の等高線タイル（z7-13、広域で使われる帯）の頂点数を抑え、MVTタイルサイズと描画コストを下げるため、Chaikin平滑化の直後にもう一段Visvalingam簡略化を追加する。

## What Changes

- `bin/lib/simplify-and-smooth.sh`の`simplify_and_smooth`関数に、Chaikin平滑化の後段で実行する2回目のVisvalingam簡略化（mapshaper `weighted`）ステップを追加する。処理順は「Visvalingam簡略化（既存, 100m=20%/500m=8%）→ Chaikin平滑化（既存, 2反復）→ Visvalingam簡略化（新規, デフォルト25%）」となる。
- 新しい環境変数`SIMPLIFY_PERCENTAGE_POST_SMOOTH`（デフォルト`25%`）を追加し、後段Visvalingam簡略化で保持する頂点の割合を制御できるようにする。`bin/make-contour-pmtiles.sh`のヘッダーコメントにも追記する。
- 後段の簡略化でも既存の`verify_simplification`（頂点数減少・自己交差なしの検証）を最終出力に対して適用し、平滑化で滑らかにした角がここで再度鋭角化しない（既存の`verify_simplification.py`の自己交差検証・頂点数減少検証を満たす）ことを保証する。
- 10m間隔の等高線には引き続きこの一連の処理（簡略化・平滑化・後段簡略化）を一切適用しない。

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `contour-pmtiles-pipeline`: 「100m・500m等高線の簡略化・平滑化」要件を、Chaikin平滑化の後にもう一段Visvalingam簡略化を適用する3段構成（簡略化→平滑化→簡略化）に変更する。

## Impact

- `bin/lib/simplify-and-smooth.sh`: `simplify_and_smooth`関数の処理順に後段Visvalingam簡略化ステップを追加。
- `bin/make-contour-pmtiles.sh`: 新しい環境変数`SIMPLIFY_PERCENTAGE_POST_SMOOTH`のデフォルト値とヘッダーコメントの追記。
- `tests/test_simplify_and_smooth.sh`: 後段簡略化により頂点数がさらに減少すること、平滑化した角の滑らかさが後段簡略化後も維持されること、10m間隔が影響を受けないことを検証するテストケースを追加。
- `openspec/specs/contour-pmtiles-pipeline/spec.md`: 「100m・500m等高線の簡略化・平滑化」要件のシナリオを更新。
