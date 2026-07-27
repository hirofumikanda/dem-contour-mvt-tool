## Context

`bin/lib/simplify-and-smooth.sh`の`simplify_and_smooth`関数は現在、100m・500m間隔の等高線ndjsonに対して次の順で処理している。

1. `mapshaper_simplify`: mapshaperの`-simplify weighted <percentage>`でVisvalingam簡略化
2. `chaikin_smooth_ndjson`: `chaikin_smooth.py`でChaikinコーナーカット平滑化（デフォルト2反復、頂点数はほぼ4倍）
3. `verify_simplification`: 簡略化前の入力と最終出力を比較し、頂点数減少・自己交差なしを検証

Chaikin平滑化が生む追加頂点の大部分は、滑らかな曲線を折れ線近似するための、ほぼ共線な点である。これを間引く後段の簡略化ステップがなく、100m・500m帯（z7-13、広域表示で使われる）のタイルが必要以上に重くなっている。

## Goals / Non-Goals

**Goals:**
- Chaikin平滑化の直後にVisvalingam簡略化をもう一段追加し、平滑化由来の冗長頂点を削減する。
- 後段簡略化のデフォルト保持率25%を新しい環境変数`SIMPLIFY_PERCENTAGE_POST_SMOOTH`で上書き可能にする。
- 既存の`verify_simplification`（頂点数減少・自己交差なし）を最終出力に対して引き続き満たす。
- 10m間隔ndjsonへの非適用という既存の不変条件を変えない。

**Non-Goals:**
- Chaikin平滑化のアルゴリズムや反復回数のロジックを変更すること。
- mapshaperの簡略化アルゴリズム（weighted Visvalingam）を別方式に変更すること。
- 100m・500m個別の1段目簡略化率（`SIMPLIFY_PERCENTAGE_100M`/`500M`）のデフォルト値を見直すこと。

## Decisions

### 後段簡略化には既存の`mapshaper_simplify`関数をそのまま再利用する
1段目と同じmapshaper `-simplify weighted`呼び出しを、平滑化後のndjsonに対して再度実行する。新しい簡略化ロジックを書かず、既存関数をChaikin出力に対してもう一度呼ぶだけにする。
- 代替案: mapshaperの`-simplify`とは別の間引きアルゴリズム（例: Douglas-Peucker）を後段に使う。 → 却下。1段目と一貫した挙動（重み付き面積基準でコーナーを保持しやすい）にする方が、平滑化で作った丸みを不自然に削らずに済む。

### `simplify_and_smooth`関数のシグネチャに後段簡略化率を追加する
`simplify_and_smooth <input> <output> <percentage> [iterations] [post_smooth_percentage]`とし、第5引数省略時は`SIMPLIFY_PERCENTAGE_POST_SMOOTH`（デフォルト`25%`）を使う。既存の呼び出し（`bin/make-contour-pmtiles.sh`、テスト）は引数を追加しなくても動作する。
- 代替案: 後段簡略化専用の新関数（例: `smooth_and_resimplify`）を作り、パイプライン側で明示的に2関数を呼ぶ。 → 却下。呼び出し側（`make-contour-pmtiles.sh`）のステップ構成を変えずに済み、「簡略化・平滑化」という1ステップの意味も保てる。

### 検証（`verify_simplification`）は最終出力に対してのみ、1段目の入力と比較する形で1回だけ実行する
中間状態（1段目簡略化後、Chaikin平滑化後）ごとの検証は追加しない。
- 理由: 既存の検証は「最終的に頂点数が減り、自己交差がない」ことを保証すれば目的を満たす。中間検証を増やすと、Chaikin平滑化直後（頂点数が一時的に入力より増える）に不要な失敗を誘発する。
- 代替案: Chaikin平滑化直後にも検証を挟む。 → 却下。平滑化直後は頂点数が意図的に増える中間状態であり、そこに「頂点数減少」の検証をかけると誤って失敗する。

### 後段簡略化でのFeature欠落（geometry: null）は1段目と同じ扱いにする
非常に強い後段簡略化率を指定した場合、mapshaperが頂点2点未満に縮退したFeatureを`geometry: null`で返すことがある。`mapshaper_simplify`の既存ロジック（該当Featureを出力から除外し、件数をstderrに出す）をそのまま再利用し、後段でも同じ扱いとする。

## Risks / Trade-offs

- [Risk] 後段簡略化率を強くしすぎると、Chaikinで丸めたコーナーが再び鋭角化し、平滑化の効果が打ち消される → Mitigation: デフォルト25%は保守的な値（平滑化後の頂点の大部分を残す）とし、`tests/test_simplify_and_smooth.sh`に「後段簡略化後も角度が元の角張った入力より緩和されたままである」ことを検証するテストケースを追加する。
- [Risk] mapshaper呼び出しが1段目・後段の2回に増え、パイプライン実行時間がわずかに伸びる → Mitigation: 対象は既に1段目簡略化・平滑化を経た軽量なndjsonであり、追加コストは小さい。許容する。
- [Risk] 非常に弱い簡略化率（環境変数で1段目・後段とも100%近くに設定するなど）を組み合わせた場合、最終頂点数が1段目簡略化前の入力を下回らずverify_simplificationが失敗する可能性は既存動作から変わらず残る → Mitigation: 後段簡略化を追加したことでむしろ最終頂点数はさらに減る方向に働くため、既存よりリスクは下がる。デフォルト値の組み合わせでは問題にならないことをテストで確認する。

