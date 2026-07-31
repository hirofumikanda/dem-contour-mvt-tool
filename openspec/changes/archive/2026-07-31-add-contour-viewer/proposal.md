## Why

`bin/make-contour-pmtiles.sh`が生成する等高線PMTiles（`build/contours.pmtiles`）は、簡略化・平滑化パラメータ（`SIMPLIFY_PERCENTAGE_*`、`CHAIKIN_ITERATIONS`等）を目視確認しながら決定する運用（README「デフォルトパラメータの決定理由」参照）だが、現状これをブラウザ上で確認する手段がない。生成物を実際に地図上に描画し、国土地理院の公式な等高線表現（最適化ベクトルタイルのstd.jsonスタイル）とスワイプ比較できるビューワが必要。

## What Changes

- `viewer/`ディレクトリ配下に、MapLibre GL JSとPMTilesパッケージを使ったブラウザビューワを新規追加する
- 左右2つの地図をスワイプ比較できるUIを追加する（[maplibre-swipe](https://github.com/hirofumikanda/maplibre-swipe)の`maplibre-gl-compare`実装を移植）
  - 左（before）: 自作の等高線PMTiles（`build/contours.pmtiles`）を、GSI最適化ベクトルタイルのstd.jsonにおける等高線レイヤー（`等高線`/`等高線数値部`、`Cntr`ソースレイヤー相当の表現）を参考にしたスタイルで描画
  - 右（after）: 国土地理院最適化ベクトルタイル（[optimal_bvmap](https://github.com/gsi-cyberjapan/optimal_bvmap)）を、そのリポジトリが配布する`std.json`スタイルで描画
- PMTilesプロトコルをMapLibreに登録し、ローカル/相対パスのPMTilesファイルをベクトルタイルソースとして直接読み込めるようにする
- 開発サーバー（Vite等）で起動しブラウザ確認できるようにし、READMEに使い方を追記する

## Capabilities

### New Capabilities
- `contour-pmtiles-viewer`: 生成した等高線PMTilesをMapLibre GL JSで描画し、国土地理院最適化ベクトルタイル（std.jsonスタイル）とスワイプ比較できるブラウザビューワ

### Modified Capabilities
(none)

## Impact

- 新規ディレクトリ`viewer/`を追加（HTML/JS/CSS一式、`package.json`によるビルドツール依存）
- 依存パッケージ: `maplibre-gl`、`pmtiles`（npm）、開発用ビルドツール（Vite想定）
- 参照する外部データ: 本リポジトリが生成する`build/contours.pmtiles`（ローカルファイル）、国土地理院の配信するoptimal_bvmap PMTilesおよびそのスタイル・スプライト・グリフ（`https://cyberjapandata.gsi.go.jp/`等、std.json内で参照されるURL）
- 既存のパイプライン本体（`bin/`配下）やテスト（`tests/`配下）には影響しない（ビューワは生成物を消費するのみ）
