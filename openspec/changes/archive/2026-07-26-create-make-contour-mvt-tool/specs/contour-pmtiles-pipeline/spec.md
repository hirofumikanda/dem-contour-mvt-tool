## ADDED Requirements

### Requirement: GeoTIFF群のVRT統合
本ツールは、指定ディレクトリ配下の複数のGeoTIFF標高DEMファイルを入力として受け取り、`gdalbuildvrt`相当の処理により1つの統合VRTファイルを生成しなければならない（SHALL）。VRT生成時、各GeoTIFFのNoData値を維持し、統合後のVRTでも同じNoData値が有効でなければならない（SHALL）。

#### Scenario: 複数GeoTIFFからVRTを生成する
- **WHEN** `tif/`配下の複数のGeoTIFF標高DEMファイルを入力としてツールを実行する
- **THEN** それら全てのGeoTIFFの範囲をカバーする単一のVRTファイルが生成される

#### Scenario: NoData値がVRTに引き継がれる
- **WHEN** 入力GeoTIFFがNoData値（-9999）を持つ
- **THEN** 生成されたVRTでも同じNoData値がNoDataとして認識される

### Requirement: 等高線間隔ごとのndjson生成
本ツールは、統合VRTから10m間隔、100m間隔、500m間隔の3種類の等高線を生成し、それぞれをndjson（改行区切りGeoJSON、1行1Feature）形式のファイルとして出力しなければならない（SHALL）。各等高線Featureには標高値を示す属性が付与されなければならない（SHALL）。

#### Scenario: 3種類の間隔で等高線ndjsonを生成する
- **WHEN** 統合VRTに対してツールを実行する
- **THEN** 10m間隔・100m間隔・500m間隔それぞれに対応する3つのndjsonファイルが生成され、各ファイルの各行が標高値属性を持つ有効なGeoJSON Featureとしてパースできる

### Requirement: 100m・500m等高線の簡略化・平滑化
本ツールは、100m間隔および500m間隔の等高線ndjsonに対して、Visvalingam法によるライン簡略化と、角の丸め（Chaikin法によるコーナーカット平滑化）を適用し、簡略化後も滑らかな形状を保った簡略化済みndjsonを生成しなければならない（SHALL）。10m間隔の等高線ndjsonに対してはこの簡略化・平滑化処理を適用してはならない（SHALL NOT）。

#### Scenario: 100m間隔の等高線を簡略化・平滑化する
- **WHEN** 100m間隔の等高線ndjsonに対して簡略化処理を実行する
- **THEN** 出力ndjsonの各ラインの頂点数が入力より減少し、かつ連続する3頂点がなす角度が入力の同じ区間より鋭角にならない（平滑化により角張りが緩和されている）

#### Scenario: 500m間隔の等高線を簡略化・平滑化する
- **WHEN** 500m間隔の等高線ndjsonに対して簡略化処理を実行する
- **THEN** 出力ndjsonの各ラインの頂点数が入力より減少し、かつ元のライン形状からの位置ずれが許容範囲内に収まる

#### Scenario: 10m間隔の等高線は簡略化しない
- **WHEN** 10m間隔の等高線ndjsonに対してパイプラインを実行する
- **THEN** タイル生成に使用される10m間隔のndjsonは、簡略化・平滑化処理を経ていない元の等高線データと一致する

### Requirement: ズームレベル対応MVT/MBTiles生成
本ツールは、10m間隔の等高線からズームレベル14、100m間隔の等高線からズームレベル11〜13、500m間隔の等高線からズームレベル7〜10のMVT（Mapbox Vector Tile）を生成し、それぞれをMBTiles形式のファイルとしてアーカイブしなければならない（SHALL）。

#### Scenario: 各間隔のMBTilesがそれぞれのズーム範囲で生成される
- **WHEN** 簡略化済みの100m間隔・500m間隔ndjsonおよび未簡略化の10m間隔ndjsonに対してタイル生成処理を実行する
- **THEN** z14のみを含む10m用MBTiles、z11-13を含む100m用MBTiles、z7-10を含む500m用MBTilesの3つが生成され、各MBTilesのメタデータのズーム範囲が指定どおりである

### Requirement: MBTiles統合とPMTiles変換
本ツールは、10m用・100m用・500m用の3つのMBTilesを1つのMBTilesファイルに統合し、さらにその統合MBTilesを1つのPMTilesファイルに変換しなければならない（SHALL）。統合後のMBTiles/PMTilesは、z7からz14までの全ズームレベルでタイルを参照できなければならない（SHALL）。

#### Scenario: 3つのMBTilesを1つに統合する
- **WHEN** z7-10用、z11-13用、z14用の3つのMBTilesに対して統合処理を実行する
- **THEN** z7からz14までの各ズームレベルのタイルを含む単一のMBTilesファイルが生成される

#### Scenario: 統合MBTilesをPMTilesに変換する
- **WHEN** 統合済みのMBTilesファイルに対してPMTiles変換処理を実行する
- **THEN** 統合MBTilesと同じズーム範囲・タイル内容を持つ単一のPMTilesファイルが生成される

### Requirement: サンプルデータによるエンドツーエンド実行
本ツールは、`tif/`配下のサンプルGeoTIFFを入力として一連の処理（VRT統合〜PMTiles変換）をエラーなく最後まで実行でき、最終成果物のPMTilesファイルが生成されなければならない（SHALL）。

#### Scenario: サンプルGeoTIFFからPMTilesを生成する
- **WHEN** `tif/`配下のサンプルGeoTIFF（2ファイル）を入力としてツール全体を実行する
- **THEN** 処理がエラーなく完了し、有効なPMTilesファイルが出力先に生成される
