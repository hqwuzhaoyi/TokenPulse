# 04: 额度、钱包与缓存数据展示

**What to build:** 用户在两种语言下准确理解套餐额度、支出预算、API 钱包余额和服务积分，并能离线查看切换语言后的旧数据。

**Blocked by:** 01 — 语言基础与首页首条完整路径

**Status:** complete（原验收及覆盖补漏已实际验证；VoiceOver听辨按用户豁免）

- [x] 本地化应用定义的窗口名称、额度周期、剩余次数、补充或到期说明及缺失、无限、耗尽、过额、旧数据和部分失败状态。
- [x] 审查所有 Provider 生成的应用自有窗口名称和单位；以稳定语义识别展示内容，不能用翻译后的字符串做额度策略或业务身份判断。
- [x] 日期、数字、百分比和货币遵循区域设置；保留 Decimal 精度、实际币种和服务单位，不换汇，不把积分或预算当成现金。
- [x] 日期精度边界保留原日历日期，跨时区不移动到前后一天、不补造午夜或精确重置时刻。
- [x] 完整短语采用可本地化插值与复数规则，覆盖零、一个和多个；保留未知值语义，不用零或无限代替缺失。
- [x] 读取历史缓存并切换语言时，不清缓存、不重新登录、不请求服务端即可正确显示可识别的应用自有标签；无法识别的服务原文保留，不猜译。
- [x] 沿用钱包展示、日期精度、Decimal 和账号状态测试，覆盖中英文、不同区域与时区；断言身份、数据、额度窗口、阈值及凭证范围均未改变。
- [x] 双语验收代表性套餐、钱包、预算、积分和混合账号详情，以及长文本、VoiceOver 和大字号。

共同约束：首期仅简体中文与英文，复用现有展示/通知行为测试边界。常用英文术语不算漏翻译；不改变 Provider API、数据身份或授权架构，不自动翻译用户输入与第三方内容。每票完成自身范围的双语行为及可视验证，不能把质量检查全部留给最后一票。

## 中央验收完成

- `02-05-behavior-tests-signed.log`：全目标781 XCTest+18 Swift Testing、0失败。最新Double精度与Demo provenance补漏后 `04-focused-verified-tests.log` 再验证18 XCTest+11 Swift Testing、0失败；没有把旧版本成功冒充后续修改已测。
- `04-ui-quotas.log`：中英7类共14真实UI test、0失败；钱包/预算/points/GPU/混合账号/日期-only/legacy标签14截图与a11y树已导出并实际查看。日期-only仅2026-10-23，不带时间；CNY/USD不换汇；points无现金符号；预算与余额分开展示。
- 可视检查发现Demo Xiaomi自有月度标题仍中文，修为明确.metadata而非猜译旧缓存；`04-ui-hybrid-verified.log` 1真实UI test通过新完整英文标题断言，截图再次查看（04-ui-hybrid-verified-attachments）。
- 原始14图中旧hybrid英文图保留作为发现记录，最终采用重验图；其余图无文本遮挡。首页最大辅助字号及a11y在01已实际验证，04所有fixture有真实a11y树。
- 精确旧未知文字保持原样；只3类新app fallback增加可选enum metadata，旧JSON缺字段读取nil，rawname/unit/ID/数值不改。Native plural语言与区域分离的96条runtime烟测及测试矩阵通过。
- 四产品无签名build和后续signed测试build均已完成；未做实机或发布。

覆盖补漏完成：681资源；125 XCTest+22Swift focused、上版798XCTest+33Swift全量绿，最后Manus native credit/credits追加后74XCTest+19Swift focused绿；8类新增producer-backed原生UI两语16case分轮全部过、16图已逐张查看；credit追加两语2UI绿、2图已看。原name/unit/scope/plan名与ID不变，Legacy nil原文保护；metadata-only旧通知升级不额外schedule且离线重绘保持原ID/time/history/fence。
