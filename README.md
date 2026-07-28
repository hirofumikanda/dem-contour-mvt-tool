# dem-contour-mvt-tool

標高DEM（GeoTIFF）から、ズームレベルごとに間隔の異なる等高線MVT（Mapbox Vector Tile）を格納したPMTilesを生成するコマンドラインツールです。

## 処理の流れ

1. **VRT統合**: 入力ディレクトリ配下の複数のGeoTIFFを`gdalbuildvrt`で1つのVRTに統合
2. **等高線抽出**: VRTから10m/100m/500m間隔の等高線を`gdal_contour`でndjson（GeoJSONSeq）として抽出
3. **簡略化・平滑化**: 100m/500m間隔の等高線に、mapshaperのWeighted Visvalingam簡略化 → Chaikinコーナーカット平滑化を適用（10m間隔は未加工のまま）
4. **タイル生成**: 間隔とズームレベルの対応（10m→z14、100m→z11-13、500m→z7-10）に従い、tippecanoeでMBTilesを生成
5. **MBTiles統合**: `tile-join`で3つのMBTilesを1つに統合
6. **PMTiles変換**: `pmtiles convert`で統合MBTilesをPMTilesに変換

各ステップの技術的な決定理由は[`openspec/changes/create-make-contour-mvt-tool/design.md`](openspec/changes/create-make-contour-mvt-tool/design.md)を参照してください。

## 前提ツール

以下のCLIツールがPATH上にインストールされている必要があります（`bin/lib/check-deps.sh`が実行時に自動チェックします）。

| ツール | 用途 |
|---|---|
| [GDAL](https://gdal.org/)（`gdalbuildvrt`, `gdal_contour`, `gdalinfo`など） | VRT統合・等高線抽出 |
| [mapshaper](https://github.com/mbloch/mapshaper) | Weighted Visvalingam簡略化 |
| [tippecanoe](https://github.com/felt/tippecanoe)（`tippecanoe`, `tile-join`） | MVT/MBTiles生成、MBTiles統合 |
| [pmtiles](https://github.com/protomaps/go-pmtiles) CLI | MBTiles→PMTiles変換・検証 |
| `sqlite3` | MBTilesのメタデータ検証 |
| Python 3 + [shapely](https://shapely.readthedocs.io/) | Chaikin平滑化、自己交差・逸脱距離の検証（`pip install shapely`） |

## 使い方

```bash
bin/make-contour-pmtiles.sh
```

デフォルトでは`tif/`配下のGeoTIFFを入力とし、`build/`配下に成果物を生成します。

```bash
INPUT_DIR=/path/to/geotiffs BUILD_DIR=/path/to/output bin/make-contour-pmtiles.sh
```

## パラメータ（環境変数）

すべて環境変数で上書き可能です（詳細は`bin/make-contour-pmtiles.sh`冒頭のコメントも参照）。

| 変数 | デフォルト | 説明 |
|---|---|---|
| `INPUT_DIR` | `<repo>/tif` | 入力GeoTIFFが置かれたディレクトリ |
| `BUILD_DIR` | `<repo>/build` | 中間生成物・最終成果物の出力先ディレクトリ |
| `DEM_NODATA_VALUE` | `-9999` | 入力GeoTIFFのNoData値 |
| `CONTOUR_INTERVAL_10M` | `10` | 最高詳細帯の等高線間隔(m) |
| `CONTOUR_INTERVAL_100M` | `100` | 中間帯の等高線間隔(m) |
| `CONTOUR_INTERVAL_500M` | `500` | 広域帯の等高線間隔(m) |
| `ZOOM_MIN_10M` / `ZOOM_MAX_10M` | `14` / `14` | 最高詳細帯のズーム範囲 |
| `ZOOM_MIN_100M` / `ZOOM_MAX_100M` | `11` / `13` | 中間帯のズーム範囲 |
| `ZOOM_MIN_500M` / `ZOOM_MAX_500M` | `7` / `10` | 広域帯のズーム範囲 |
| `SIMPLIFY_PERCENTAGE_100M` | `20%` | 100m間隔の等高線に適用するVisvalingam簡略化で保持する頂点の割合 |
| `SIMPLIFY_PERCENTAGE_500M` | `8%` | 500m間隔の等高線に適用するVisvalingam簡略化で保持する頂点の割合 |
| `CHAIKIN_ITERATIONS` | `2` | Chaikin平滑化の反復回数 |
| `CONTOURS_LAYER_NAME` | `contours` | MVTのレイヤー名 |

### デフォルトパラメータの決定理由

- **`SIMPLIFY_PERCENTAGE_100M=20%` / `SIMPLIFY_PERCENTAGE_500M=8%`**: 500m間隔はより低いズーム帯（z7-10、広域表示）で使われるため、100m間隔（z11-13）より強い簡略化にしている。値はサンプルデータ（`tif/`配下）で生成したPMTilesを確認して決定した。
- **`CHAIKIN_ITERATIONS=2`**: 合成した直角コーナー（90°）の折れ線に対する検証（`tests/test_simplify_and_smooth.sh`）で、2回の反復により約153°まで角が緩和されることを確認しており、「角張らない滑らかな形状」という目的を満たしている。また`chaikin_smooth.py`は簡略化前の頂点数を超えないよう反復回数をFeatureごとに自動抑制する仕組み（`--budget-ndjson`）を持つため、デフォルト値を無闇に増やしても既に抑制されがちな小さなラインへの効果は限定的である。

これらのパラメータの技術的な背景は[`design.md`のDecisionsセクション](openspec/changes/create-make-contour-mvt-tool/design.md)にも記録されている。

## 出力物

`BUILD_DIR`（デフォルト`build/`）配下に生成される主なファイル：

| ファイル | 説明 |
|---|---|
| `merged.vrt` | 統合VRT |
| `contours-10m.ndjson` / `contours-100m.ndjson` / `contours-500m.ndjson` | 間隔ごとの等高線（ndjson、未簡略化） |
| `contours-100m.simplified.ndjson` / `contours-500m.simplified.ndjson` | 簡略化・平滑化済みの等高線（ndjson） |
| `contours-10m.mbtiles` / `contours-100m.mbtiles` / `contours-500m.mbtiles` | 間隔ごと・ズーム範囲ごとのMBTiles |
| `contours.mbtiles` | 統合MBTiles（z7-z14） |
| `contours.pmtiles` | **最終成果物**（z7-z14） |

## ビューワ

`viewer/`配下に、生成した等高線PMTilesをMapLibre GL JSで描画し、国土地理院最適化ベクトルタイルとスワイプ比較できるブラウザビューワがあります。

### 使い方

```bash
# 1. 等高線PMTilesを生成（未生成の場合）
bin/make-contour-pmtiles.sh

# 2. ビューワの依存パッケージをインストールして起動
cd viewer
npm install
npm run dev
```

表示されたローカルURL（デフォルト`http://localhost:5173/`）をブラウザで開くと、左に自作の等高線PMTiles、右に国土地理院最適化ベクトルタイル（`std.json`スタイル）が表示され、中央のハンドルをドラッグしてスワイプ比較できます。一方の地図をパン・ズームすると、もう一方も追従します。

`viewer/public/contours.pmtiles`は`build/contours.pmtiles`へのシンボリックリンクとして配信されるため、**`viewer`を起動する前に`bin/make-contour-pmtiles.sh`を実行し、`build/contours.pmtiles`を生成しておく必要があります**。`build/contours.pmtiles`が存在しない状態でビューワを起動すると、このシンボリックリンクがリンク切れとなり、自作等高線のPMTilesソースを読み込めません。

比較対象の国土地理院最適化ベクトルタイルは、[gsi-cyberjapan/optimal_bvmap](https://github.com/gsi-cyberjapan/optimal_bvmap)が配布する`style/std.json`をそのまま`viewer/src/styles/gsi_std.json`としてローカル複製したものを使用しています（`glyphs`/`sprite`/タイル本体は同スタイル内の絶対URLをそのまま参照するため追加のベンダリングはしていません）。複製元が更新された場合は、以下のコマンドで再取得してください。

```bash
curl -o viewer/src/styles/gsi_std.json \
  https://raw.githubusercontent.com/gsi-cyberjapan/optimal_bvmap/main/style/std.json
```

## テスト

```bash
bash tests/run_tests.sh
```

サンプルGeoTIFF（`tif/`配下）を使い、各ステップの単体テスト・パイプライン全体のエンドツーエンドテスト・異常系（NoDataのみのGeoTIFF、標高が完全に一定なGeoTIFF、範囲が重ならない複数GeoTIFFなど）のテストを実行します。GDAL/mapshaper/tippecanoeを実際に呼び出すため、完了まで数分かかります。
