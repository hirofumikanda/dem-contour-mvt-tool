## Context

`tif/`配下に複数枚の標高DEM（GeoTIFF、JGD2011/EPSG:6668、NoData=-9999、Float64）が置かれており、これらから等高線PMTilesを生成するCLIツールを新規作成する。実行環境には GDAL 3.8（`gdalbuildvrt`, `gdal_contour`, `ogrinfo`）、tippecanoe 2.78、tile-join、mapshaper 0.6、go-pmtiles CLI、Python 3.14、Node.js がすべてインストール済みであることを確認済み。ネットワーク接続もあり、pipで追加パッケージ（例: shapely, numpy）を導入可能。

パイプラインは以下の4段階：
1. VRT統合
2. 等高線抽出（10m/100m/500m間隔、ndjson）
3. 簡略化・平滑化（100m/500mのみ）→ MVT化（MBTiles）
4. MBTiles統合 → PMTiles変換

## Goals / Non-Goals

**Goals:**
- `tif/`配下のGeoTIFF群を入力として、1コマンド（シェルスクリプトまたはMakefile経由）でPMTilesを生成できること
- 等高線間隔とズームレベルの対応（10m→z14、100m→z11-13、500m→z7-10）を満たすこと
- 100m・500m間隔の等高線について、Visvalingam簡略化とChaikin平滑化を組み合わせ、角張らない滑らかな簡略化形状を生成すること
- 中間生成物（VRT、ndjson、個別MBTiles）を検証・再利用しやすいよう明示的なファイルとしてディスクに残すこと
- サンプルデータ（`tif/`内2枚のGeoTIFF）でエンドツーエンドに動作確認できること

**Non-Goals:**
- 任意の入力ディレクトリ・任意のCRS・任意の等高線間隔への一般化（将来拡張の余地は残すが、本変更ではハードコードされた3段階間隔を前提とする）
- タイル配信サーバーの構築やホスティング
- 差分更新・インクリメンタル再生成（毎回フルリビルドを前提とする）
- 大規模日本全国データセットでの性能最適化（サンプルデータでの動作を優先）

## Decisions

### 1. パイプライン全体を1本のシェルスクリプト（`bin/make-contour-pmtiles.sh` 等）＋補助スクリプトで構成する
GDAL・tippecanoe・tile-join・pmtilesはいずれもCLIツールであり、シェルから逐次呼び出すのが最も依存が少なくシンプル。平滑化ロジックのみ後述の理由でPythonスクリプトとして切り出す。
- 代替案: Node.js/Pythonで全処理をラップするランナーを書く → CLIツールの単純な連結には過剰であり却下。ただし将来的にオーケストレーションが複雑化した場合はNode/Pythonラッパーへの移行を検討する。

### 2. 等高線抽出は `gdal_contour -f GeoJSONSeq` を使う
`GeoJSONSeq`（RFC 8142準拠のndjson）は`gdal_contour`が直接出力できるフォーマットであり、追加の変換ステップが不要。`-i <interval>`で間隔を指定し、`-a elevation`で標高値を属性として付与する（タイルのプロパティとして利用）。
- 代替案: GeoJSON（FeatureCollection）を生成してから`ogr2ogr`でndjsonに変換 → 余計な中間ファイルとI/Oが増えるため不採用。

### 3. 簡略化はmapshaperのWeighted Visvalingam、平滑化は自前実装のChaikin法を「簡略化→平滑化」の順で適用する
- mapshaperはVisvalingam（および重み付きVisvalingam）簡略化をネイティブにサポートしており、`-simplify weighted percentage=<n>%`または`interval=<meters>`で等高線の実効面積に基づく間引きができる。ズームごとに簡略化強度（percentageまたはinterval）を変えることで、z11-13用とz7-10用で異なる簡略度を作る。
- Visvalingamで間引いた後の頂点はまだ角張っている（特に強い簡略化をかけた場合）ため、そのままではズームアウト時に折れ線が目立つ。そこでChaikinのコーナーカット法（各エッジを1:3, 3:1で分割し新頂点列を作る操作をNイテレーション適用）を後段にかけ、線を滑らかな曲線に近づける。
- Chaikin法はGDAL・mapshaperいずれにもビルトイン実装がないため、Python（標準ライブラリのみ、依存追加なし）でndjsonを1行ずつ読み、各Feature（LineString/MultiLineString）の座標配列にChaikin反復を適用して書き戻す小スクリプトとして実装する。反復回数（デフォルト2〜3回）と、始点・終点を保持する（閉曲線でない限りコーナーカットで端点が動かないよう固定する）ロジックを持たせる。
- 適用順序を「簡略化→平滑化」にする理由: 先に平滑化すると頂点数が増え、後段の簡略化アルゴリズムの効きが変わり計算量も増える。先に間引いてから滑らかにする方が、狙った簡略度を保ちながら見た目を改善できる。
- 10m間隔（z14）は簡略化・平滑化を行わない（原設計どおり、最高詳細ズームでは原形状を保持）。
- 代替案: シェイプリー（shapely）の`simplify()`はDouglas-PeuckerのみでVisvalingamに非対応のため不採用。トポロジー保持の観点でmapshaperを採用（`-simplify`はデフォルトで自己交差の修復<no-repair指定なし>を行う）。
- 実装時の追補（頂点数増加の回避）: Chaikinの1反復は頂点数をほぼ2倍にするため、簡略化で強く間引かれた小さなライン（局所ピークを囲む短いループ等）では、固定の反復回数を適用すると簡略化前の頂点数を上回ってしまうことが実データで判明した（例: 100m間隔の一部ラインで20点→簡略化後5点→Chaikin2回で20点、正味の減少なし）。この対策として、Chaikin適用前のndjson（＝簡略化前のオリジナル頂点数）を「予算」として各Featureに渡し、`予算を下回る範囲で最大の反復回数`をFeatureごとに自動選択するようにした（`bin/lib/chaikin_smooth.py`の`--budget-ndjson`）。これにより全Featureで「簡略化・平滑化後の頂点数 < 簡略化前の頂点数」を厳密に満たす。
- 実装時の追補（自己交差判定の実装手段）: 簡略化・平滑化後のラインは数千頂点規模になることがあり、純Pythonの総当たり（O(n^2)）自己交差判定は現実的な時間で終わらないことが実データで判明した。そのため、自己交差判定と最大逸脱距離の計算に限り、GEOS（shapely）の`is_simple`/`distance`を利用する（`bin/lib/verify_simplification.py`）。Chaikin平滑化自体は引き続き標準ライブラリのみで実装している。`bin/lib/check-deps.sh`はPythonモジュールとして`shapely`が利用可能かも検証する。

### 4. タイル生成はtippecanoeで間隔ごとに個別MBTilesを作り、tile-joinで統合する
- `tippecanoe -o <interval>.mbtiles -Z<min> -z<max> -l contours -L<layer> <ndjson>`のように、10m/100m/500mそれぞれ独立にMBTilesを生成する。ズーム範囲が重ならない設計（z7-10 / z11-13 / z14）のため、レイヤー名を共通（例: `contours`）にしても同一ズームで複数間隔が競合しない。
- 生成した3つのMBTilesは`tile-join -o combined.mbtiles a.mbtiles b.mbtiles c.mbtiles`で1つのMBTilesに統合し、最後に`pmtiles convert combined.mbtiles output.pmtiles`でPMTiles化する。
- 代替案: 最初から1本のndjsonを結合してtippecanoe1回で処理する → 間隔ごとに簡略化パラメータが異なり、ズーム範囲も別々に指定する必要があるため、個別生成＋tile-join統合の方が制御しやすく採用。
- 実装時の追補（tippecanoe自身の内部簡略化を無効化）: `--no-line-simplification`を指定せずに生成すると、tippecanoeはそのデータセットのmaxzoom（例: 100m間隔ならz13）であっても内部の簡略化アルゴリズムでラインの頂点を間引くことを実データで確認した（例: 事前に簡略化・平滑化した10頂点のラインがz13タイル内で8頂点に減少）。Visvalingam簡略化・Chaikin平滑化で意図的に作った形状をtippecanoe側で上書きさせないよう、全てのtippecanoe呼び出しに`--no-line-simplification`を指定する。サンプルデータでは`--force`（既存出力の上書き）と合わせてもタイルサイズに関する警告は出ないことを確認済み。

### 5. 中間生成物はビルドディレクトリ（例: `build/`）配下に間隔・ズームがわかるファイル名で出力する
再実行時のデバッグ・部分的な再生成を容易にするため、`build/merged.vrt`, `build/contours-10m.ndjson`, `build/contours-100m.simplified.ndjson`, `build/contours-10m.mbtiles`等、各ステップの成果物を明示的なファイルとして残す。

## Risks / Trade-offs

- [Visvalingam簡略化とChaikin平滑化のパラメータ調整が主観的] → サンプルデータで生成したPMTilesを実際にビューア（例: maplibre-gl等）で目視確認し、パラメータ（percentage/interval、Chaikin反復回数）をデフォルト値として決定・文書化する。パラメータはスクリプト引数として外出しし、後から調整可能にする。
- [Chaikin平滑化の自前実装にバグがあると等高線の位相（トポロジー）が壊れる（自己交差等）] → 実装後、生成ndjsonに対し`ogrinfo`や簡単なジオメトリ検証（自己交差チェック）をテストで実施する。
- [gdal_contourの`-a`属性名やGeoJSONSeqのRS(0x1E)区切り有無がtippecanoeの読み込みと整合しない可能性] → 実データで各ステップの出力を`ogrinfo`/`head -c`等で検証しながら疎通確認する。
- [複数GeoTIFFのVRT統合時にNoData(-9999)の扱いを誤ると誤った等高線が出る] → `gdalbuildvrt`に`-srcnodata -9999 -vrtnodata -9999`を明示し、`gdal_contour`側も`-snodata`または`-inodata`で無視することをタスクで確認する。
- [tippecanoeのデフォルトの簡略化・座標丸めが、事前に施したChaikin平滑化結果を上書き・劣化させる可能性] → タイル化時は`--no-simplification-of-shared-nodes`等は不要だが、tippecanoe自体の内部簡略化（ズームごとの自動簡略化）を弱める、または無効化するオプション（例: `-pS`/`--no-line-simplification`は最高ズームでのみ等、要検証）を検討し、事前に施した形状ができるだけ保持されるようにする。

## Open Questions

- Chaikin反復回数・Visvalingamのpercentage/intervalの具体的なデフォルト値は、サンプルデータでの目視確認結果を踏まえてtasks実施時に確定する。
- 出力ファイル名・レイヤー名・属性スキーマ（標高値プロパティ名など）の最終的な命名規則。
