## Context

`bin/make-contour-pmtiles.sh`は`build/contours.pmtiles`（z7-14、レイヤー名`contours`、属性`elevation`（標高、数値）と`ID`を持つLineString）を生成する。このPMTilesを目視確認する手段が現状ない。

参考実装として2つの既存リソースを調査した。

- [`hirofumikanda/maplibre-swipe`](https://github.com/hirofumikanda/maplibre-swipe)（自作リポジトリ）: Vite構成、`maplibregl.Compare`（`mapbox-gl-compare`をMapLibre向けに移植した`src/maplibre-gl-compare.js`/`.css`を自プロジェクトにベンダリング）で2つの`maplibregl.Map`をスワイプ比較する最小構成。`pmtiles`パッケージを依存に持つが、`index.html`ではCDN版`maplibre-gl`を`<script>`タグで読み込んでいる。
- [`gsi-cyberjapan/optimal_bvmap`](https://github.com/gsi-cyberjapan/optimal_bvmap): 国土地理院最適化ベクトルタイルのサンプルビューワ。`style/std.json`は`glyphs`/`sprite`/`sources.v.tiles`すべてを`https://cyberjapandata.gsi.go.jp/`または`https://gsi-cyberjapan.github.io/optimal_bvmap/`の絶対URLで参照しているため、`std.json`ファイル自体をローカルに複製すればスプライト・グリフ・タイル本体は追加のベンダリングなしにネットワーク越しにそのまま参照できる。ソースは`pmtiles://https://.../optimal_bvmap-v1.pmtiles/{z}/{x}/{y}`形式で、`pmtiles`ライブラリの`Protocol`を`maplibregl.addProtocol("pmtiles", ...)`で登録して利用している。
- `std.json`内の等高線関連レイヤーは`等高線`（line、`source-layer: Cntr`、色`rgb(200,160,60)`、`vt_alti % 50 == 0`の計曲線を太く・低ズームでは計曲線のみ表示）と`等高線数値部`（symbol、`vt_code == 7352`のみに標高値ラベルを`line-center`配置）の2層構成。

## Goals / Non-Goals

**Goals:**
- `viewer/`配下に、`npm run dev`等のコマンドでブラウザ確認できる静的ビューワ一式を追加する
- 自作の等高線PMTiles（`build/contours.pmtiles`）と国土地理院最適化ベクトルタイル（`std.json`スタイル）を左右スワイプで比較できること
- 自作PMTilesのスタイルは、GSIの`等高線`/`等高線数値部`レイヤーの表現（色・計曲線強調・標高ラベル）を参考に、自作データのレイヤー名`contours`・属性`elevation`に合わせて作成すること
- ビューワの追加が既存のパイプライン本体（`bin/`, `tests/`）に影響しないこと

**Non-Goals:**
- ビューワのホスティング・デプロイ（GitHub Pages公開等）は本変更のスコープ外（ローカル確認用途に限定）
- 複数地域・複数PMTilesファイルの切り替えUIなど、比較確認以上の機能拡張
- GSIの`Cntr`レイヤーが持つ全属性（`vt_code`による地形図記号分類等）の完全な互換表現。あくまで等高線の色・太さ・ラベルの見た目を参考にするに留める

## Decisions

### 1. `viewer/`はVite製の独立フロントエンドプロジェクトとする
`maplibre-swipe`と同じくVite（`npm run dev`/`npm run build`）を採用する。ライブラリはCDN`<script>`タグではなくnpm依存（`maplibre-gl`, `pmtiles`）としてESモジュールでimportする（`maplibre-swipe`の`package.json`は両方式が混在しているため、本変更ではESモジュール方式に統一する）。
- 代替案: プレーンなHTML+CDN scriptタグのみで完結させる → ビルド不要で最も手軽だが、`pmtiles`パッケージのESモジュールAPI（`Protocol`）を素直に使うにはバンドラがあった方が依存管理・将来の拡張がしやすいため不採用。

### 2. スワイプUIは`maplibre-swipe`の`maplibre-gl-compare`実装をそのまま移植する
`src/maplibre-gl-compare.js`/`.css`を`viewer/src/`配下にベンダリングし、`main.js`で`new maplibregl.Compare(beforeMap, afterMap, "#comparison-container")`として使う。右クリックでフィーチャ属性をハイライト表示するデバッグ用ハンドラ（`setupContextMenuHandler`）も、生成した等高線の属性（`elevation`/`ID`）確認に有用なため踏襲する。
- 代替案: `@maplibre/maplibre-gl-compare`公式npmパッケージを使う → 参考実装として明示的に指定された`maplibre-swipe`リポジトリの構成に合わせることを優先し、同リポジトリのベンダリング方式を踏襲する。

### 3. 左（before）＝自作コンター、右（after）＝GSI最適化ベクトルタイルとして固定する
`beforeMap`に自作`contours.pmtiles`＋自作コンタースタイル、`afterMap`に`std.json`（国土地理院最適化ベクトルタイル）を割り当てる。初期表示の中心・ズームは自作PMTilesの`bounds`/`center`（`pmtiles show build/contours.pmtiles`で取得: 中心付近 `[138.065, 35.362]`、z14相当）に合わせる。

### 4. GSIの`std.json`はネットワーク越しにそのまま参照せず、`viewer/src/styles/gsi_std.json`としてリポジトリにローカル複製する
`std.json`自体（レイヤー定義のJSON）は`optimal_bvmap`リポジトリから取得してローカルファイルとして複製する。ファイル内が参照する`glyphs`/`sprite`/`sources.v.tiles`は絶対URL（`https://cyberjapandata.gsi.go.jp/...`, `https://gsi-cyberjapan.github.io/optimal_bvmap/...`）のままとし、追加でベンダリングしない（オフライン動作は本変更のスコープ外）。
- 代替案: 実行時に`fetch`でGitHub上の`std.json`を都度取得する → 参照先リポジトリの更新やネットワーク状態に描画結果が左右され再現性が落ちるため、ローカル複製を採用。更新が必要な場合は手動で再取得する運用とする。

### 5. 自作コンタースタイル（`viewer/src/styles/contours.json`）はGSIの`等高線`/`等高線数値部`を参考に、自作データのスキーマ（レイヤー名`contours`、属性`elevation`）向けに書き起こす
- 線色はGSIと同じ`rgb(200,160,60)`を踏襲する。
- 計曲線（太線）強調は、ズーム帯ごとに実際にタイルへ格納されている等高線間隔（z7-10→500m間隔、z11-13→100m間隔、z14→10m間隔、README/`bin/lib/generate-tiles.sh`のズーム対応表に一致）を踏まえ、各ズーム帯で「間隔の5倍ごと」を計曲線として太く描画する（z14: `elevation % 50 == 0`、z11-13: `elevation % 500 == 0`、z7-10: 計曲線強調なし・一律の太さ。500m間隔は既に粗いため）。GSIのように単一の`% 50`をズーム共通で使わず、ズーム帯ごとに異なる`case`式を`step`（ズーム）で切り替える。
- 標高ラベル（`等高線数値部`相当）はsymbolレイヤーとして追加し、`symbol-placement: line-center`、`text-field: ["get", "elevation"]`とし、計曲線に該当する等高線のみラベルを表示する（GSIが`vt_code == 7352`の専用ラベル用フィーチャのみラベル表示するのと同等の見た目にするため、線フィーチャそのものに対し計曲線条件でフィルタする）。
- 代替案: GSIの`Cntr`レイヤーのペイント式をそのまま流用し属性名だけ`vt_alti`→`elevation`に置換する → GSIは全ズーム共通の`vt_alti % 50`判定を前提にしているが、これは元データが常に10m間隔であることに依存しており、間隔がズームごとに変わる自作データにそのまま適用すると意図しない太線パターンになるため不採用。

### 6. 自作PMTiles（`build/contours.pmtiles`）はシンボリックリンク経由でViteの`public/`から配信する
`viewer/public/contours.pmtiles`を`../../build/contours.pmtiles`へのシンボリックリンクとしてリポジトリにコミットする。Viteの開発サーバーは`public/`配下をそのまま静的配信するため、シンボリックリンクをたどって常に最新の`build/contours.pmtiles`が配信される。スタイルJSON側は`pmtiles://./contours.pmtiles`のような相対参照でこのファイルを指す。
- 代替案A: `vite.config.js`の`server.fs.allow`を使い`../build`を直接参照する → publicディレクトリ外の絶対パス配信は追加設定が煩雑で、シンボリックリンクの方が単純。
- 代替案B: `npm run dev`前に`build/contours.pmtiles`を`viewer/public/`へコピーするスクリプトを用意する → コピー忘れで古いデータを見てしまう事故を避けるため、常に最新を指すシンボリックリンクを採用。
- リスク: Windows環境ではシンボリックリンクの作成に管理者権限またはDeveloper Mode有効化が必要な場合がある。本リポジトリの開発環境はLinux（WSL2）であるため許容する。

### 7. `pmtiles`プロトコルの登録は`viewer/src/main.js`内で一度だけ行う
`optimal_bvmap`の実装と同様、`import { Protocol } from "pmtiles"; const protocol = new Protocol(); maplibregl.addProtocol("pmtiles", protocol.tile);`を`main.js`冒頭で実行し、自作スタイル・`gsi_std.json`の両方の`pmtiles://`ソースで共通利用する。

## Risks / Trade-offs

- [GSIの`std.json`が将来更新された場合、ローカル複製が古くなる] → READMEに複製元URLと再取得手順を明記し、必要に応じて手動更新する運用とする。
- [計曲線判定のズーム帯ごと`case`式が、README側のズーム対応表（`bin/lib/generate-tiles.sh`）と将来ズレる可能性] → スタイルJSON内にコメント（またはREADME）でズーム対応表との対応関係を明記し、パイプライン側のズーム設定変更時に追従が必要である旨を残す。
- [シンボリックリンクがgit clone後や`build/`未生成の状態でリンク切れになる] → READMEに「先に`bin/make-contour-pmtiles.sh`を実行してから`viewer`を起動する」前提を明記する。

## Open Questions

(なし。既存リポジトリ2件の調査により技術的な不明点は解消済み)
