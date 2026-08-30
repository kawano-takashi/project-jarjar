# Project JARJAR 現在の状態

- 更新日: 2026-08-30 (JST)
- 状態: **ユーザーによるMVP最終調整待ち**
- playable baseline: 未固定（revision 2 作業ツリー）
- balance revision: `2`
- 正式playtest target: 未固定

## 現在地

装備システムをbalance revision 2として「武器3枠＋お守り3枠」へ一本化した。スキル、防具、UNIQUE、
ワイルド素材と専用経路は撤去済み。3武器は個別の自動攻撃として同時稼働し、お守りは武器または
プレイヤー全体へ固定値を加算する。戦利品と合成の出力は同じ武器／お守り生成規則を使い、W1最初の
報酬だけ武器を保証する。W8は戦闘終了時に通常7個＋Legendary 1個を付与し、最後の品も装備して
最終スコアへ反映できる。倉庫と合成のコントローラーナビゲーションは画面配置どおりの空間移動へ
修正済みで、十字キー、左スティック、キーボード矢印が同じ上下左右経路を使う。

現行GDScript全回帰は `TEST_SUMMARY passed=54 failed=0`。装備、戦利品、合成、戦闘、UI、score、
balance revisionが変わったため、revision 1以前のRelease検証、手動QA、playtest対象・結果はすべて無効であり、
現候補へ流用しない。ユーザー最終調整と正式プレイテストが未完了のため、正式受入またはMVP完成ではない。

## 次の作業

1. ユーザーがエフェクト、文言その他のMVP最終調整を行う。
2. 調整完了の明示後、全回帰、GDScript検査、性能試験、Release export、pack audit、smoke、手動QAを実施する。
3. 新identity用の `docs/final-qa.md` に手動QAと自動検証結果を人間が記録する。
4. 手動QA合格後、新しい候補HEAD、EXE/PCK SHA-256、balance revisionを `artifacts/playtest/target.txt` へ手動で固定する。
5. その後だけ `docs/playtest-protocol.md` を有効化し、未経験者5人以上が各3runを実施する。

候補HEAD、EXE、PCK、balance revisionのいずれかが変わった場合、旧対象、旧QA、旧playtestデータを流用しない。
人間の参加、回答、計測値をエージェントが生成または補完してはならない。

## 正式受入後の棚卸し

5人×3run完了までは、現行の回帰テスト、Debug QA、性能試験、Release検証、GDScript guard、比較用buildを保持する。
正式受入後に再棚卸しし、配布・保守に不要な資材を削除する。
