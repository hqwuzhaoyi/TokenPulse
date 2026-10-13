# 10 最终验收汇总（2026-10-13）

**原范围验收完成，root已统一关闭01—10（10/10）。**用户仅豁免VoiceOver实际听辨及语音导航，未执行/未称通过；必要辅助label/value/hint仍由源码/native资源/语义与已有AX证据核查。水平swipe工具未测、完整Watch内部AX树不可导出的限制如实保留，原票没有逐一种手势或导出整树的独立门槛，不能冒称这些工具项已通过。

此汇总为最终证据对照，不自行改工单状态。未测试实机或TestFlight，未提交/推送/发布。根代理GUI原始图与操作记录以root工具记录为准，不将shared renderer或编辑器预览冒充系统实际宿主。

## 逐票实际证据

| 票 | 原验收范围及事实证据 |
| --- | --- |
| 01 | `issues/01-language-and-home.md`/01日志：两语Home、空态、演示、详情、最大字和native AX，Demo身份/fallback；四目标native资源构建。 |
| 02 | `02-evidence.md`：两语搜索/aliases/index真实tap C/drag Z、原用户输入、direct/gateway四Save UI与最大字/AX；VoiceOver实际听辨用户豁免。 |
| 03 | `03-evidence.md`：Google/JetBrains/device code两语6原生UI，开始/复制/打开/取消/恢复及既有授权行为；fixture URL handled不等于真实网络登录。 |
| 04 | `04-evidence.md`/`04-supplement-evidence.md`：14 quota UI、16 producer-backed补漏UI、2credit UI与实图；scope/plan/model/未知unit原文、Decimal/currency/date-only/旧JSON升级；VoiceOver豁免。 |
| 05 | `05-evidence.md`：两语Switch修改/恢复，真实compact删除Sheet外部取消，长解释滚动、大字/AX与既有同步/删除行为；VoiceOver豁免。 |
| 06 | `06-evidence.md`：未来提醒content替换、semantic缓存重启/fence/ID/time/history保护；zh真实Demo和en真实quota系统通知。原英文demo组locator失败保留，不计绿；后台时机按系统调度。 |
| 07 | `07-evidence.md`：70XCTest+12Swift函数、Home7场景×两语14UI/14图，最大字4UI/8图；真实Refresh取消/保留失败，empty/history/expired整块隐藏，来源原文与AI非官方语义不变。 |
| 08 | `08-cua-recheck.md`/`08-09-cua-continuation.md`/toolbar evidence：两语empty→demo/刷新、Nous开始→原code/URL→取消、设置选DeepSeek/恢复Claude/退出、error恢复、完整长名最大字真实滚动；正常MiniMax→真实组件入口到Claude详情。WatchPresentation三项独立缓存/授权/刷新行为；root按原票关闭，不把水平swipe未测写通过。 |
| 09 | `09-evidence.md`/renderer reviews/续验/`09-watch-final-host-check.md`：真实iPhone extension主屏两语绑定、同包ZH→EN→ZH及原锁屏三family两语；长名/完整Decimal/状态/date-only原生shared矩阵全图实查。Watch真实系统en/en_US与恢复zh-Hans-CN/zh_CN下Circular/Rectangular/Corner/Inline四支持family及SmartStack均有实际非编辑宿主结果，保留已存contexts与正常App选择/刷新。Corner数值、Rect钱包缺金额与窄英文title三真实缺陷已最小修并真宿主确认。 |
| 10 | 本汇总、最新coverage JSON/人工有限域账本、区域/时区/fallback/复数/date-only/离线缓存/身份/通知既有测试、最终四产品构建与针对性回归、必要辅助语义检查；原范围无剩余阻塞，root已关闭。 |

## 最新源验证：顺序执行，复用缓存

- `final-rect-four-target-debug-build.log`：最新四产品Debug签名 **BUILD SUCCEEDED**；`final-rect-four-target-release-build.log`：最新四产品Release无签名 **BUILD SUCCEEDED**。jobs1，按顺序完成；Debug/Release主App均无预览多余Metadata.appintents。
- `final-rect-platform-watch-focused.log`：Platform26+WatchPresentation3=**29 tests/0fail TEST SUCCEEDED**。
- `final-rect-wallet-ocr-ui.log`：新增两语rect wallet真实像素OCR **2UI/0fail TEST SUCCEEDED**。OCR均读取完整`1,234.56789012 USD`，两个原生截图已view，英文Wallet balance/中文钱包余额与更新时间完整。附件`final-rect-wallet-ocr-ui/manifest.json`；不是只查AX而漏掉画面缺金额。该测试为原生shared160×72 renderer，不能替代root真Watch宿主证据。
- `final-signed-behavior-tests.log`：798XCTest+33SwiftTesting=**831全量基线通过**；最后credit补漏后`04-credit-final-focused.log`74+19通过。之后纯布局源码使用上面29focused和两语新可视测试，不假称831对最新每行重跑，不无因再跑全套。
- 所有最后命令、日志和环境范围在`final-rect-validation.md`。自有776冷bootstatus报DataMigrationFailed但实际Booted、29+2真实执行通过，原环境日志保留；未碰root Watch/DE11/用户设备。

## 最终资源与diff静态检查

命令：`python3 .scratch/internationalization/10-coverage-preflight.py > .scratch/internationalization/10-coverage-preflight-tool.log 2>&1`；`git diff --check`。

681 keys、14 native plural、387L10n calls/301解析literal keys、35动态有限域；catalog/plural/format/literal missing/manual-domain/source-location均0error；四产品各1次同一catalog引用，diffcheck通过。API Key/Token/OAuth/Provider、品牌/model/用户和第三方原文例外保留，不做全球替换。

Native emit原始未入catalog4类均确认例外：`%@`原始实体title/subtitle、JetBrains `central-…`标识前缀、品牌Apple Watch、示例URL，不构成app-owned说明遗漏；fragment canonical英文差异已有中央resolution。原补漏前发现另存快照，不被最后0error掩盖。最新完整产物为preflight JSON/人工账本。

## 最终宿主范围与限制

root最后`09-watch-final-host-check.md`明确：EN Corner45%与钱包110CNY、Inline DEMO·CLAUDE63%、Circle/Rect正常额度/更新和SmartStack54%/完整title/110CNY；恢复CN后Corner54%、SolarGraph演示·CLAUDE45%、模块circle/rect45%/中文5小时额度/未来reset、正常SmartStack54%及110CNY/钱包余额/更新时间、回实际表盘circle/rect110CNY完整。原失败host图保留，正常非编辑宿主通过，不将短暂旧预览缓存算最终结果。更新时机受系统预算，部分通过Edit→Done触发原context刷新，没有删除重建账号或伪造timeline。

VoiceOver实际听辨/导航仅按用户豁免，不称通过；App水平swipe工具未测，不改原`.page`掩盖限制。必要辅助标签仍须正确，不把这些限制变成新的整树/逐一种手势交付门槛。未做真实设备/TestFlight发布，本次验收为模拟器实际系统宿主与原生视图。

## “完整 AX 树”是否是票标准

**不是原始规格或08/09/10票要求的独立交付物。** 原始spec user story30要求“translated accessibility labels, values and hints”；Accessibility and layout要求本地化spoken descriptions；08要求代表性小屏/两语/长名/大字号/触控及原先VoiceOver；09要求两语长名及辅助功能；10要求所有app-owned可见/辅助文案覆盖。没有“必须导出所有Watch内部AX节点”的要求。先前把完整树不可取得列为单独阻塞是验证手段被扩大为标准，应该收敛为**必要label/value/hint语义的验证范围**，不能宣称树已取得。

用户只豁免实际VoiceOver音频/导航，**没有豁免辅助文案正确性**。此轮以下有限覆盖仍成立：

| 必要辅助语义 | 当前核查证据 | 限制 |
| --- | --- | --- |
| gear入口 | WatchAccountPagesView:65显式本地化label“表盘设置”，native string emit/catalog两语完整；root两语真点击/导航通过 | App runtime AX不可读，未声称该节点已导出 |
| 账号名/已选 | 行combine，L10n.demoAccountName保护原name，显式已选择/未选择value；checkmark与ProviderIcon隐藏避免重复；root两语选择/返回可见状态 | runtime combine朗读顺序没有音频验收 |
| Gauge额度 | 单独可见title隐藏重复AX；Gauge label用共享windowDisplayName/value用usage；831及04行为覆盖两语、未知/耗尽/完整unit/date | watch内部运行时AX未直接读取；共享真实native renderer/Phone AX不能冒充Watch树 |
| 刷新 | 显式“刷新”label、“正在刷新”value和“独立查询此账号的最新额度”hint；两语catalog/native emit完整，root真实刷新结果通过 | tool内部AX不暴露，未记录实际读出hint |
| 授权码/打开 | WatchNousAuthorizationView:27 code label/value分离，原始code不翻译；打开hint由L10n完整format原host；root两语真实开始/打开/取消通过 | fixture URL handled；语音导航按用户豁免 |
| Widget额度/错误/更新 | WidgetContentPresentation完整a11ySummary，circle/rect/inline/corner合并label，原missing不造0；Platform既有测试与两语shared native AX/真iPhoneAX有证据 | Watch宿主完整AX仍未取得，不能扩称各family辅助节点均被直接实测 |

因此**无法导出整棵Watch树本身不应增加阻塞**；应记录为工具观测限制，并依据上述源/资源/native语义与行为证据评估必要辅助文案。若root发现具体关键label漏译/丢值仍必须修复；本判断没有把“音频豁免”扩大成“全部辅助标签豁免”，也不假称实际Watch内部AX通过。08真实账号浏览与关键触控流程已满足原范围；每种水平手势不是原票独立门槛。09所有四种支持Watch family与SmartStack已由root两语真实宿主验收，无剩余family阻塞；工单由root统一关闭。
