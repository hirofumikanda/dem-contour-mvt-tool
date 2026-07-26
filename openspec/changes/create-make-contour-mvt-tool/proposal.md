## Why

標高DEM（GeoTIFF）から等高線ベクトルタイル（PMTiles）を生成する作業は現在手作業で、GDALやtippecanoeの個別コマンドを都度組み立てる必要があり再現性がない。ズームレベルごとに異なる等高線間隔（10m/100m/500m）を使い分け、かつ低ズームでは線形状を滑らかに簡略化する、という要件を満たす一貫したパイプラインが存在しないため、これを1本のスクリプトとして整備する。

## What Changes

- 複数のGeoTIFF（標高DEM）を統合するVRT生成ステップを追加する
- VRTから等高線間隔10m/100m/500mのndjson（改行区切りGeoJSON）を生成するステップを追加する
- 100m間隔・500m間隔の等高線に対して、Visvalingam法によるライン簡略化とChaikin法によるスムージングを、角張らず滑らかな形状を保つ順序・パラメータで適用するステップを追加する（10m間隔は簡略化しない）
- 等高線間隔とズームレベルの対応（10m→z14、100m→z11-13、500m→z7-10）に従いtippecanoeでMBTilesを生成するステップを追加する
- 3種類のMBTilesを1つのMBTilesおよびPMTilesに統合するステップを追加する
- `tif/`配下のサンプルGeoTIFFを使ったエンドツーエンド実行で、パイプライン全体が動作することを検証する

## Capabilities

### New Capabilities
- `contour-pmtiles-pipeline`: GeoTIFF群からVRT生成→等高線抽出→簡略化/平滑化→MVTタイル化→PMTiles統合までを一気通貫で実行するコマンドラインツール

### Modified Capabilities
(none)

## Impact

- 新規スクリプト（VRT構築、等高線抽出、簡略化・平滑化、タイル生成、タイル統合の各処理を含む）を追加
- 依存ツール: GDAL（`gdalbuildvrt`, `gdal_contour`）、tippecanoe/tile-join、PMTiles変換ツール、ライン簡略化・平滑化を行うライブラリまたはスクリプト
- 実行対象データ: `tif/`配下のGeoTIFF（テスト用サンプル）
- 出力: 中間生成物（VRT、ndjson、MBTiles）および最終成果物（統合MBTiles、PMTiles）
