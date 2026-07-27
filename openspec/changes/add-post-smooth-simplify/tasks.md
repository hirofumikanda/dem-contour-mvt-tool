## 1. 後段Visvalingam簡略化の実装 (Issue: #19)

- [x] 1.1 `bin/lib/simplify-and-smooth.sh`に環境変数`SIMPLIFY_PERCENTAGE_POST_SMOOTH`（デフォルト`25%`）を追加する
- [x] 1.2 `simplify_and_smooth`関数を、第5引数（省略時は`SIMPLIFY_PERCENTAGE_POST_SMOOTH`）を受け取るように拡張し、Chaikin平滑化の出力に対して既存の`mapshaper_simplify`を再度呼び出す後段簡略化ステップを追加する
- [x] 1.3 `verify_simplification`の呼び出しが、1段目の入力と後段簡略化後の最終出力を比較する形のまま変わっていないことを確認する
- [x] 1.4 `bin/make-contour-pmtiles.sh`のヘッダーコメントに`SIMPLIFY_PERCENTAGE_POST_SMOOTH`の説明を追記する

## 2. テスト (Issue: #20)

- [ ] 2.1 `tests/test_simplify_and_smooth.sh`の合成角張りラインのテストに、Chaikin平滑化直後の頂点数より最終出力の頂点数が少ないことを検証するアサーションを追加する
- [ ] 2.2 同テストに、後段簡略化後も最小角度が簡略化・平滑化前の入力より緩和されたままである（角度チェックが後段簡略化を経ても崩れない）ことを検証するアサーションを追加する
- [ ] 2.3 実サンプルデータ（100m/500m）のテストが、後段簡略化ステップ追加後も頂点数減少・自己交差なしを満たすことを確認する（既存アサーションのまま通ることを確認）
- [ ] 2.4 10m間隔ndjsonがパイプライン全体を経ても元データと完全一致することを検証する既存テストが、後段簡略化追加後も変わらず通ることを確認する
- [ ] 2.5 `tests/run_tests.sh`経由で全テストスイートを実行し、既存テストに回帰がないことを確認する

## 3. 動作確認 (Issue: #21)

- [ ] 3.1 `bin/make-contour-pmtiles.sh`を`tif/`のサンプルデータでエンドツーエンド実行し、`SIMPLIFY_PERCENTAGE_POST_SMOOTH`のデフォルト値で最終PMTilesが生成されることを確認する
- [ ] 3.2 `SIMPLIFY_PERCENTAGE_POST_SMOOTH`を明示的に指定して実行し、値を変えると後段簡略化の効き方（最終頂点数）が変わることを確認する
