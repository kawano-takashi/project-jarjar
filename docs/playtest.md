# Project JARJAR プレイテスト

## 成功基準

**5人以上が各3回遊び、全回答の70%以上が「また遊びたい」なら成功。**

各run後の質問は「また遊びたいですか」の1問だけとする。
経験の有無や入力方式は自由とし、気になった点や不具合は任意でメモする。

## 対象と準備

- 最終調整完了のユーザー明示: なし

ユーザーが最終調整完了を明示した後、[AGENTS.md](../AGENTS.md) の検証・export・Verifyを実施する。
`Verify` が表示した3値を次の欄と `artifacts/playtest/target.txt` へ手入力する。

```text
candidate_head=<40hex>
exe_sha256=<64hex>
pck_sha256=<64hex>
```

EXE/PCKまたは候補HEADが変わったら対象を更新し、別の対象の回答を混ぜて集計しない。
自分で試遊する場合は `.\tests\release.ps1 -Task ManualQa` を使う。

## 実施と回答の記録

参加者ごとに `T01` のようなログ用IDを付け、同じRelease buildを次のコマンドで起動する。

```powershell
.\tests\release.ps1 -Task Playtest -TesterId T01
```

各参加者は3run遊び、各run終了後に「また遊びたいですか」へyes/noで答える。
聞き手は [記録用CSV](playtest-results.csv) に参加者ID・run番号（1〜3）・回答を1行ずつ記録する。

3run終了後にゲームを閉じると、実ユーザー設定が復元される。
終了コード0はセッション終了だけを表す。途中で終了した場合も、得られた回答だけを残し、未回答を補完しない。

## 集計と結果

CSVはUTF-8、1行目をヘッダーとし、回答は小文字の `yes` / `no` だけを使う。
参加者IDとrun番号の組を重複させず、5人以上の全参加者にrun 1〜3の回答が揃ってから集計する。
`yes数 ÷ 全回答数` が70%以上なら成功。割合を丸めずに判定する（15回答ならyesが11件以上）。

- 実施日:
- 参加人数・有効回答数: 未確認
- 「また遊びたい」のyes数・割合: 未確認
- 判定: 未実施
- メモ（任意）:

人間の回答や観察事実をエージェントが生成・補完しない。

## 技術的な検証記録

- ソース検証（2026-09-05、Godot 4.7.2-stable）: 全回帰147/147 PASS、全リソース170件の事前ロードPASS
- GDScript guard: 102ファイルPASS、変更GDScript check-only: 20/20 PASS
- PowerShell構文・差分整合性検査: PASS（Release buildでの実行は未実施）
- Full HD性能試験・Release export・Verify: 未実施
