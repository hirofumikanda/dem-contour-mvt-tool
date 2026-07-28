## 1. プロジェクト雛形の作成

- [ ] 1.1 `viewer/`ディレクトリを作成し、`package.json`（`type: module`、`dev`/`build`/`preview`スクリプト、依存`maplibre-gl`・`pmtiles`、devDependency`vite`）を追加する
- [ ] 1.2 `viewer/vite.config.js`を追加する
- [ ] 1.3 `viewer/index.html`を追加し、`#comparison-container`配下に`#before`/`#after`の地図コンテナを配置する
- [ ] 1.4 `viewer/.gitignore`（`node_modules`、`dist`等）を追加する

## 2. スワイプ比較UIの移植

- [ ] 2.1 `hirofumikanda/maplibre-swipe`の`src/maplibre-gl-compare.js`と`maplibre-gl-compare.css`を`viewer/src/`にベンダリングする
- [ ] 2.2 `viewer/src/main.js`で`pmtiles`の`Protocol`を`maplibregl.addProtocol("pmtiles", ...)`に登録する
- [ ] 2.3 `main.js`で自作コンタースタイルを使う`beforeMap`とGSI `std.json`スタイルを使う`afterMap`を作成し、`maplibregl.Compare`でスワイプ結合する
- [ ] 2.4 2つの地図の初期中心・ズームを`build/contours.pmtiles`のデータ範囲（富士山周辺、z14相当）に合わせる

## 3. 自作等高線PMTilesの配信

- [ ] 3.1 `viewer/public/contours.pmtiles`を`../../build/contours.pmtiles`へのシンボリックリンクとして作成する
- [ ] 3.2 `build/contours.pmtiles`が存在しない場合の挙動（開発サーバー起動前提条件）をREADMEに明記する

## 4. 自作コンタースタイルの作成

- [ ] 4.1 `gsi-cyberjapan/optimal_bvmap`の`style/std.json`から`等高線`/`等高線数値部`レイヤーの定義を確認し、線色（`rgb(200,160,60)`）を控える
- [ ] 4.2 `viewer/src/styles/contours.json`を作成し、`sources`に`pmtiles://./contours.pmtiles`を指すベクトルソース（レイヤー名`contours`）を定義する
- [ ] 4.3 z7-10（500m間隔）・z11-13（100m間隔、`elevation % 500 == 0`を計曲線）・z14（10m間隔、`elevation % 50 == 0`を計曲線）でズーム帯ごとに線幅を切り替えるlineレイヤーを定義する
- [ ] 4.4 計曲線に該当する等高線に`elevation`属性を`line-center`配置で表示するsymbolレイヤーを定義する

## 5. GSI最適化ベクトルタイルスタイルの取り込み

- [ ] 5.1 `gsi-cyberjapan/optimal_bvmap`の`style/std.json`を取得し、`viewer/src/styles/gsi_std.json`としてリポジトリにローカル複製する
- [ ] 5.2 複製元URLと再取得手順をREADMEまたはスタイルファイル近傍に記録する

## 6. 動作確認とドキュメント

- [ ] 6.1 `bin/make-contour-pmtiles.sh`実行後に`viewer`で開発サーバーを起動し、自作等高線とGSI最適化ベクトルタイルの両方が描画されることをブラウザで確認する
- [ ] 6.2 スワイプハンドルの操作、および一方の地図のパン・ズームがもう一方に追従することをブラウザで確認する
- [ ] 6.3 計曲線の太線強調と標高ラベル表示をブラウザで確認する
- [ ] 6.4 リポジトリのREADMEに`viewer/`の使い方（前提条件、起動コマンド）を追記する
