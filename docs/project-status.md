# Project JARJAR 現在の状態

- 更新日: 2026-08-29 (JST)
- 状態: **ユーザーによるMVP最終調整待ち**
- playable baseline: `97671bd1efd5a139081f5a97f59f0083aacddf1f`
- balance revision: `0`
- 正式playtest target: 未固定

## 現在地

コーディングエージェントによるMVP基準版の実装と最終調整前QAは完了している。全自動検証は
`TEST_SUMMARY passed=105 failed=0`、通常Releaseの連続E2Eは人間確認を含めて完了扱いとなった。
ただし、ユーザー最終調整と正式プレイテストが未完了のため、Gate 6合格またはMVP完成ではない。

現在の `build/windows/ProjectJARJAR.exe`、`ProjectJARJAR.console.exe`、
`ProjectJARJAR.pck` は最終調整前の比較用であり、正式プレイテストには使わない。参考identityは
`exe_sha256=4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668;pck_sha256=cc092adf0d93ba9a11023f8634631821701462eaed37bb55121aab2243d7502b`。

## 次の作業

1. ユーザーがエフェクト、文言その他のMVP最終調整を行う。
2. 調整完了の明示後、全回帰、GDScript検査、性能試験、Release export、pack audit、smoke、手動QAを実施する。
3. 新しい候補HEAD、Release build identity、balance revisionを固定し、`artifacts/gate-06/playtest-target.txt`へ記録する。
4. 新identity用の `docs/final-qa.md` を新規作成し、手動QAと自動検証結果を記録する。
5. その後だけ `docs/playtest-protocol.md` を有効化し、未経験者5人以上が各3runを実施する。

候補HEAD、EXE、PCK、balance revisionのいずれかが変わった場合、旧対象、旧QA、旧playtestデータを流用しない。
人間の参加、回答、計測値をエージェントが生成または補完してはならない。

## 第2段階の棚卸し

5人×3run完了までは、回帰テスト、Debug QA、性能試験、Release保守経路、GDScript guard、比較用buildを保持する。
正式受入後にこれらを再棚卸しし、配布・保守に不要な資材を削除する。
