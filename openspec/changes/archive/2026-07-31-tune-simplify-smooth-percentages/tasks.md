## 1. 現状把握とベースライン比較 (Issue: #38)

- [x] 1.1 `bin/make-contour-pmtiles.sh`をデフォルト値のまま`tif/`のサンプルデータで実行し、`build/contours.pmtiles`を生成する
- [x] 1.2 `viewer`の開発サーバーを起動し、z11・z13（100m帯の両端）およびz7・z10（500m帯の両端）で、自作等高線と国土地理院最適化ベクトルタイル（`std.json`）をスワイプ比較し、現状のデフォルト値（`SIMPLIFY_PERCENTAGE_100M=20%`, `SIMPLIFY_PERCENTAGE_500M=8%`, `CHAIKIN_ITERATIONS=2`, `SIMPLIFY_PERCENTAGE_POST_SMOOTH=25%`）で見られる差異（角張り過多／丸め過ぎ、頂点密度の違いなど）を書き出す

## 2. 100m帯（z11-13）のパラメータ調整 (Issue: #39)

- [x] 2.1 `SIMPLIFY_PERCENTAGE_100M`（1回目のVisvalingam簡略化）を候補値に変えて`bin/make-contour-pmtiles.sh`を再実行し、`viewer`でz11・z13を国土地理院最適化ベクトルタイルと比較する
- [x] 2.2 `CHAIKIN_ITERATIONS`と`SIMPLIFY_PERCENTAGE_POST_SMOOTH`（2回目のVisvalingam簡略化）を候補値に変えて同様に再実行・比較し、100m帯で最も近似した組み合わせを暫定決定する

## 3. 500m帯（z7-10）のパラメータ調整と最終値決定 (Issue: #40)

- [x] 3.1 `SIMPLIFY_PERCENTAGE_500M`（1回目のVisvalingam簡略化）を候補値に変えて`bin/make-contour-pmtiles.sh`を再実行し、`viewer`でz7・z10を国土地理院最適化ベクトルタイルと比較する
- [x] 3.2 `CHAIKIN_ITERATIONS`・`SIMPLIFY_PERCENTAGE_POST_SMOOTH`は100m帯と共有パラメータのため、2章で暫定決定した値のまま500m帯でも許容できる見た目になっているか確認する。許容できない場合は100m帯・500m帯双方を見比べながら妥協点を再調整する
- [x] 3.3 4パラメータの最終値を決定する

## 4. デフォルト値・ドキュメントの更新 (Issue: #41)

- [x] 4.1 `bin/lib/simplify-and-smooth.sh`の4つのデフォルト値（`SIMPLIFY_PERCENTAGE_100M`, `SIMPLIFY_PERCENTAGE_500M`, `CHAIKIN_ITERATIONS`, `SIMPLIFY_PERCENTAGE_POST_SMOOTH`）を最終決定値に更新する（#39, #40の結論により数値は現状のまま変更なし。既に最終決定値と一致していることを確認した）
- [x] 4.2 `bin/lib/simplify-and-smooth.sh`冒頭のコメント（デフォルト値決定理由）を、国土地理院最適化ベクトルタイルとの比較で決定した旨に更新する
- [x] 4.3 `bin/make-contour-pmtiles.sh`のヘッダーコメント（デフォルト値の記載）を最終決定値に更新する（数値は変更なしのため、既存記載のままで最終決定値と一致していることを確認した）
- [x] 4.4 README「パラメータ（環境変数）」表のデフォルト値列を最終決定値に更新する（あわせて表から漏れていた`SIMPLIFY_PERCENTAGE_POST_SMOOTH`の行を追加した）
- [x] 4.5 README「デフォルトパラメータの決定理由」を、国土地理院最適化ベクトルタイルとどのズーム・地物で比較し何を優先したかを含む内容に書き直す

## 5. 検証 (Issue: #42)

- [x] 5.1 `tests/run_tests.sh`を実行し、デフォルト値変更後も既存テストスイート全体が回帰なく通ることを確認する
- [x] 5.2 `bin/make-contour-pmtiles.sh`を最終デフォルト値でエンドツーエンド実行し、`build/contours.pmtiles`が生成されることを確認する
- [x] 5.3 `viewer`で最終成果物と国土地理院最適化ベクトルタイルを改めてz11・z13・z7・z10でスワイプ比較し、1.2で書き出した差異が改善していることを確認する（#39・#40の結論通り数値は変更していないため、z13は良好なまま、z11・z10は構造的な要因により未解消のまま。詳細は`verification.md`）
