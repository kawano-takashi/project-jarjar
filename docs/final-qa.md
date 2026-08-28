# Project JARJAR Gate 6 最終QA

- 実施日: 2026-08-28 (JST)
- Gate 5承認済みHEAD: `8bf0a4545de6f4b0ecb754afa0a149c2327b4b9f`
- balance revision: `0`
- 最終調整前QA Release build identity: `exe_sha256=4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668;pck_sha256=cc092adf0d93ba9a11023f8634631821701462eaed37bb55121aab2243d7502b`
- 判定: **合格（最終調整前QA）**。全11項目を閉じた。手順10は2026-08-28の明示的人間承認を含む。Gate 6全体はユーザー最終調整と正式プレイテストが未完了のため未合格。

`PASS` は原則として画面を目視し、該当process logger区間の終了コード0とstderr空まで確認した
項目だけに付ける。clean-settings wrapperを使う項目では、さらに
`appdata_nonsettings ... match=true`を確認する。手順10だけは、現identityの8wave完走RESULTと
表示seedを目視し、以前の実機FAILED確認を含めて完了扱いとする2026-08-28の明示的人間承認を
例外として記録する。自動scenarioを実機手動QAへ読み替えない。

| # | QA項目 | 状態 | 実測・注記 |
|---:|---|---|---|
| 1 | 通常Debugをゲームパッドだけで2回起動 | PASS | 2026-08-28の実機報告で、手順1〜3のうちスティックによるUIフォーカス連続移動以外は問題なし。TITLE／設定はGodot標準フォーカス経路で、修正前後の実JoypadMotion回帰testでも1 tilt 1 moveを確認。戦闘中の左スティック移動は連続入力が仕様であり今回の修正対象外。 |
| 2 | `reward_controls`をゲームパッドだけで4方式 | PASS | 同じ実機報告で、スティックによるUIフォーカス連続移動以外は問題なし。REWARD_REVEALはGodot標準フォーカス経路で修正対象外。固定4報酬、通常自動、A長押し4倍、Y全開封、アクセシビリティ設定時の代替表示は問題なしと報告された。 |
| 3 | `inventory_controller`をゲームパッドだけで全操作 | PASS | 比較、item／skill操作、B取消、X lock、一括選択、廃棄、合成、wild、overflow、次戦、王冠時skill slot skipは問題なしと報告された。独自フォーカス経路で左スティック保持中に無限巡回する不具合を修正し、`FocusController.direction_for_event()`へのエッジ判定集約、保持中JoypadMotionの消費、実イベント回帰testがPASS。2026-08-28に修正後Debug QA状態で「1回倒すと1移動、保持中は停止、neutral後の次入力で1移動」を実機再確認しPASS。 |
| 4 | `pre_quota_death` | PASS | 実施時のprocess loggerでscenario ID、exit 0、stderr空を確認し、次tick後のW1 FAILED、cleared wave 0、獲得箱0を目視。`tests.txt`は最終全suite再実行で更新されたため当時labelは現行logに残らないが、目視画像と報酬破棄の自動scenarioは保持。 |
| 5 | `pre_quota_timeout` | PASS | 実施時のprocess loggerでscenario ID、exit 0、stderr空を確認し、次tick後のW1 FAILED、cleared wave 0、獲得箱0を目視。`tests.txt`は最終全suite再実行で更新されたため当時labelは現行logに残らず、目視画像を保持。 |
| 6 | `post_quota_death` | PASS | 次tick後のREWARD_REVEALで未開封箱1を目視し、その後INVENTORYの通常枠に報酬が保持されたことを確認。 |
| 7 | `immortal_100` | PASS | 接触中もHP 100/100。報復の鐘は初回5hitで発火し0/5へ戻り、その後2/5まで再進行する表示を連続観測。実ダメージ0は自動scenarioでも照合。 |
| 8 | `boss_299` | PASS | 299/300、BOSS必須、通常spawn停止を目視。移動後にBOSS撃破、通常spawn再開、300到達、報酬8件（初期装備込み所持品9件）、W8整理、RESULTまで確認。 |
| 9 | `result_controller`の4導線 | PASS | 4回の別起動でseed 20260827、撃破102、超過20、箱160、合成12、最高DPS 999、装備6枠、skill2枠、戦闘9,000、build 3,055、合計12,055を照合。同seed、新seed、TITLE、終了を各1回確認。 |
| 10 | 同一Release buildの通常UI連続E2E | PASS（人間承認） | 現identityの通常Releaseでseed `7268298430057356136`、8wave完走、獲得箱204、合成82、RESULT、score `42850 + 26855 = 69705`を提供画像で目視。後半のFAILED／retry経路とprocess終了には現実走logがないが、以前の実機FAILED確認を含めて完了扱いとする2026-08-28の明示指示を受領した。詳細は `artifacts/gate-06/release-e2e.md`。 |
| 11 | 同一seed・同一入力の自動replay | PASS | `artifacts/gate-06/tests.txt` の `gate03_deterministic_replay_and_dense_500_contract` が敵ID/type/positionを照合し、`gate04_reward_payload_presentation_and_determinism_contract` がRewardRoll全fieldとloot RNG決定性を照合する。 |

## 手動証跡

- `artifacts/gate-06/manual-pre-quota-death-final.png`
- `artifacts/gate-06/manual-pre-quota-timeout-final.png`
- `artifacts/gate-06/manual-post-quota-death-reward.png`
- `artifacts/gate-06/manual-immortal-100-before.png`
- `artifacts/gate-06/manual-immortal-100-after.png`
- `artifacts/gate-06/manual-boss-299-initial.png`
- `artifacts/gate-06/manual-boss-299-after-move.png`
- `artifacts/gate-06/manual-boss-299-result.png`
- `artifacts/gate-06/manual-result-new-focused.png`
- `artifacts/gate-06/manual-result-title-focused.png`
- `artifacts/gate-06/manual-result-exit-focused.png`
- `artifacts/gate-06/manual-release-final-title.png`
- `artifacts/gate-06/manual-release-final-tutorial-before.png`
- `artifacts/gate-06/manual-release-final-tutorial-after.png`
- `artifacts/gate-06/manual-release-final-failed.png`
- `artifacts/gate-06/manual-release-final-return-title.png`

末尾5件の`manual-release-final-*`は旧identityの部分実走であり、現identityの手順10証跡へ流用しない。

## 自動検証との対応

- 最終全suite: `TEST_SUMMARY passed=105 failed=0`
- GDScript guard: 110 files、Python syntax drift 0。変更7 scriptのGodot 4.7.2 `--check-only`成功。
- 性能: 平均348.189968fps、p95 4.460ms、1% low 201.979398fps、worst 12.246ms、memory ratio 1.006634284、count／pool／effect-chain／orphan違反0。
- Release: 一時copy smoke成功、pack 190 paths／必須2／禁止0、固定外manifest・QA/debug/test引数20件を期待どおり終了2で拒否。
- ゲームパッド主要導線・pointer event 0: `gate06_controller_only_primary_routes_and_zero_pointer_contract`
- スティック1 tilt 1 move・neutral再arm・D-pad／修飾キー付き矢印非退行: `gate06_left_stick_focus_moves_once_per_tilt`
- 3解像度UI: `gate06_ui_focus_shape_labels_and_resolution_contract`
- 固定死亡／時間切れ／ノルマ後死亡: `gate03_death_timeout_same_tick_and_full_heal_flow`、`gate03_qa_scenario_contract`
- 100%軽減: `gate05_immortal_hit_and_dps_window_contract`
- overflow／全開封／retry／終了: Gate 4・Gate 5の該当scenario群

## 残作業

1. ユーザーがエフェクト、文言その他のMVP最終調整を行う。
2. 調整後に全自動検証、性能、Release export、pack audit、smoke、最終QAを再実施し、新しいidentityを固定する。
3. **Gate 6プレイテスト待ち**へ移行し、調整へ関与していない未経験tester 5人以上×各3runを実施する。
