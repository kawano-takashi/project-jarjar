# Project JARJAR 現在の状態

- 更新日: 2026-08-29 (JST)
- 状態: **ユーザーによるMVP最終調整待ち**
- playable baseline: `97671bd1efd5a139081f5a97f59f0083aacddf1f`
- balance revision: `0`
- 正式playtest target: 未固定

## 現在地

コーディングエージェントによるMVP基準版の実装と最終調整前QAは完了している。現行GDScript全回帰は
`TEST_SUMMARY passed=103 failed=0`、通常Releaseの連続E2Eは人間確認を含めて完了扱いとなった。
ただし、ユーザー最終調整と正式プレイテストが未完了のため、正式受入またはMVP完成ではない。

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
