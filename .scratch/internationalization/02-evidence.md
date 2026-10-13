# 02 实施证据

## 当前结论（2026-10-13）

2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。 本票按更新后的范围 complete。中央构建/回归与后续原生 UI、大字号证据见本文件后文和 progress.md；下文早期“待执行/未验证”为保留的历史阶段，不代表当前状态。

状态：in-progress。源实施与静态检查完成，双语实际运行、原生索引操作与可视验收尚未完成；不记为 complete。

已实施：

- AddAccountView 所有 API Key 分支的静态字段/说明纳入资源；动态地区说明、controller 自有 credentialLabel、OpenAI 自有 connectionNotice、登录按钮、凭证区 header/footer、保存失败提示均通过 L10n 查询完整短语。
- Provider 品牌名保留；国内/国际、钱包和 Legacy 余额等自有描述根据语言查询。ProviderRegion 与 AlibabaTokenPlanSite 仅修改展示。按负责人协调，RefreshFailure 的全部 12 个自有错误也查询原生资源；支持显式 language 用于展示测试。
- ProviderSelectionCatalog 是添加页面使用的唯一展示目录。搜索包含两种语言名称、既有别名、Provider rawValue；名称排序、已有服务分组、剩余分组与原生 index label 共享此目录。非拉丁首字分组使用稳定 `#` 标识和可翻译的“其他”标题；英文 Zhipu 进入 Z，中文智谱进入 #。
- 空搜索结果提供自有中英文提示，查询内容作为格式参数原样显示。Provider 行继续支持换行与原生 selected accessibility trait。
- 未修改 Provider rawValue、凭证 API、Region/Site rawValue、QuotaWindow、原始服务文本、用户输入或既有 demo 账号命名存储行为；未修改共享 catalog/pbxproj。

资源片段：`fragments/02.json`，89 个条目。片段可交负责人合并。

2026-10-11 实际已运行检查：

- `xcrun swiftc -frontend -parse TokenPulse/UI/AddAccountView.swift TokenPulse/Domain/Models.swift TokenPulse/Domain/AccountConfiguration.swift TokenPulseTests/ProviderSelectionTests.swift .scratch/internationalization/02-quota-test-snippet.swift`：exit 0。只证明 Swift 语法，不证明目标类型检查/运行。
- `git diff --check -- TokenPulse/Domain/Models.swift TokenPulse/Domain/AccountConfiguration.swift`：exit 0。
- Python 静态覆盖 audit：AddAccount 42、Provider/Region 16、RefreshFailure 12、Site 2、controller 中文 credentialLabel 15、OpenAI notice 1 个自有中文字面量均无缺片段。搜索别名是保留原文的匹配数据；保存时已有 demo name prefix 是既有数据行为，均有意排除。
- JSON parse 与格式占位符签名 audit：89 条解析成功，`%@` / `%ld` 的中英签名一致。

测试已写，尚未执行：

- 新 `TokenPulseTests/ProviderSelectionTests.swift`：负责人需加入 test target。覆盖双语/英文 fallback 搜索别名、无结果、已有服务、完整目录/分组/index一致、组内排序、Region/Site 展示以及 Moonshot 凭证范围/缺地区失败/自定义账号名与 raw enum 的保存身份。
- `.scratch/internationalization/02-quota-test-snippet.swift`：按负责人协调由05代理串行追加 `QuotaMonitorTests.swift`，复用该文件 private 存储与查询替身。直接 miniMaxChina Key 和 newAPI 网关都覆盖保存成功、恢复、Key和地址范围保持，以及账号存储失败后的凭证回滚/不发查询。语言参数验证显示不改变上述存储行为；应用实际有效语言仍需下述双语 UI 执行。

剩余明确验证：

1. 负责人合并02片段、将新测试文件加入 target、05追加保存测试后，串行运行 ProviderSelectionTests 与两个新增 QuotaMonitorTests。回归既有 NewAPIProviderTests / MoonshotProviderTests / AlibabaTokenPlanProviderTests；使用合成凭证。
2. 无签名 TokenPulse target build 验证应用、Watch与两 widget 目标的共享 Models/L10n 和原生资源编译；不要把 parse 作为 build 成功。
3. en 与 zh-Hans 真正点击“添加账号→更换→搜索”，测试智谱/Zhipu与无结果；清空搜索，点击并拖动 Z/M/# 原生字母索引，验证到达相应组，已有服务 ★ 可达。
4. 两种语言分别输入直接 Key 与 newAPI 网关 fixture，完成保存与失败提示；地区 provider 更换地区/站点仍清空凭证。检查 Moonshot/Alibaba Coding Plan/Token Plan、GitKraken organization、Volcengine、xAI、IBM Bob、OpenAI branch 文案。
5. 截图检查长 credentialLabel/Provider 名与最大辅助字号；VoiceOver检查 Provider选中状态、字段名与操作文本。静态源码保留 native selected trait，但未真实运行 VoiceOver，不记通过。

## 原生表单保存结果

`02-05-ui-actions-recovery.log` 中 AccountSaveAcceptance 4 个中英文 direct/gateway 测试全部真实通过（总轮因05失败为 TEST FAILED，不能整轮计绿）。四张 saved 账号截图已导出并实际查看：用户原文姓名与品牌未改写；部分图被系统 Password AutoFill 保存提示覆盖，背景保存账号确实可见，此提示采用系统语言，后续截图将正常 dismiss。现有行为成功/失败回归及原生索引 tap/drag 证据保留。大字号、原生 AX 名称另行检查，实际 VoiceOver 听辨未验证。

## 大字号修复与最终中文重验

真实最大辅助字号英文Provider header原HStack挤压，已改accessibilitySize下竖排（保留原始品牌、原生NavigationLink与普通字号水平分布）；私有label/layout分解使Swift正常编译。四产品unsigned与signed均绿。两语目录/form真实截图全部查看，英文最大字UI通过，中文最终`02-ui-large-zh-final.log` 1test0fail，toolbar Save等待native转场后断言。Native AX包含搜索提示、品牌、选中状态/字段/更换/保存等完整语义；实际VoiceOver听辨未执行，仍待设备。
