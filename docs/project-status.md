# Project JARJAR 現在の状態

- 更新日: 2026-08-30 (JST)
- 状態: **ユーザーによるMVP最終調整待ち**
- playable baseline: 未固定（revision 1 作業ツリー）
- balance revision: `1`
- 正式playtest target: 未固定

## 現在地

W8ボス限定UNIQUE装備への移行をbalance revision 1として実装した。通常・エリート・fallback・合成から
UNIQUEを除外し、W8ボスの8箱を非UNIQUE 7箱＋UNIQUE 1箱に固定している。現行GDScript全回帰は
`TEST_SUMMARY passed=118 failed=0`。loot仕様とbalance revisionが変わったため、以前のRelease検証、手動QA、
playtest対象は現候補へ流用しない。ユーザー最終調整と正式プレイテストが未完了のため、正式受入または
MVP完成ではない。

## 次の作業

1. ユーザーがエフェクト、文言その他のMVP最終調整を行う。
2. 調整完了の明示後、全回帰、GDScript検査、性能試験、Release export、pack audit、smoke、手動QAを実施する。
3. 新identity用の `docs/final-qa.md` を新規作成し、手動QAと自動検証結果を記録する。
4. 手動QA合格後、新しい候補HEAD、EXE/PCK SHA-256、balance revisionを `artifacts/playtest/target.txt` へ手動で固定する。
5. その後だけ `docs/playtest-protocol.md` を有効化し、未経験者5人以上が各3runを実施する。

候補HEAD、EXE、PCK、balance revisionのいずれかが変わった場合、旧対象、旧QA、旧playtestデータを流用しない。
人間の参加、回答、計測値をエージェントが生成または補完してはならない。

## 正式受入後の棚卸し

5人×3run完了までは、現行の回帰テスト、Debug QA、性能試験、Release検証、GDScript guard、比較用buildを保持する。
正式受入後に再棚卸しし、配布・保守に不要な資材を削除する。
