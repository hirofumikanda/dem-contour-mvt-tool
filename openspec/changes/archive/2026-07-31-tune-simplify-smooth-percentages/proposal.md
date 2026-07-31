## Why

`bin/lib/simplify-and-smooth.sh`が100m/500m間隔の等高線に適用する3段階処理（1回目のVisvalingam簡略化 → Chaikin平滑化 → 2回目のVisvalingam簡略化）のデフォルト値（`SIMPLIFY_PERCENTAGE_100M=20%`, `SIMPLIFY_PERCENTAGE_500M=8%`, `CHAIKIN_ITERATIONS=2`, `SIMPLIFY_PERCENTAGE_POST_SMOOTH=25%`）は、これまでサンプルデータで生成したPMTilesを単独で目視確認して決定されてきた。`add-contour-viewer`で国土地理院最適化ベクトルタイル（`std.json`）とのスワイプ比較ビューワが使えるようになった今、z13以下（z11-13の100m間隔、z7-10の500m間隔）の等高線が国土地理院の公式な簡略化・平滑化の見た目にどれだけ近いかを直接比較できる。現状のデフォルト値は国土地理院の形状と比較して決定されたものではないため、比較しながらパーセンテージを調整し、より近い形状に更新する。

## What Changes

- `bin/lib/simplify-and-smooth.sh`の4つのデフォルト値（`SIMPLIFY_PERCENTAGE_100M`, `SIMPLIFY_PERCENTAGE_500M`, `CHAIKIN_ITERATIONS`, `SIMPLIFY_PERCENTAGE_POST_SMOOTH`）を、`viewer`のスワイプ比較で国土地理院最適化ベクトルタイル（z7-13の等高線表現）と見比べながら調整し、より近似した値に更新する
- `bin/make-contour-pmtiles.sh`のヘッダーコメントおよびREADMEのパラメータ表・デフォルト値決定理由を、更新後の値と「国土地理院最適化ベクトルタイルとのスワイプ比較で決定した」という決定根拠に合わせて更新する
- パラメータ調整の過程・比較結果・最終的に採用した値の根拠を`design.md`に記録する（既存の`create-make-contour-mvt-tool`/`add-post-smooth-simplify`のDecisionsと同じ形式）

## Capabilities

### New Capabilities
(なし)

### Modified Capabilities
- `contour-pmtiles-pipeline`: 「100m・500m等高線の簡略化・平滑化」要件に、デフォルトのパーセンテージ・反復回数が国土地理院最適化ベクトルタイルの形状に近似するよう決定されなければならない、という基準を追加する

## Impact

- `bin/lib/simplify-and-smooth.sh`: 4つのデフォルト値とその根拠コメント
- `bin/make-contour-pmtiles.sh`: ヘッダーコメントのデフォルト値表記
- `README.md`: パラメータ表・デフォルトパラメータの決定理由
- 挙動が変わるのはデフォルト値のみで、`simplify_and_smooth`関数のインターフェース・処理順序・既存テストのアサーションは変更しない
