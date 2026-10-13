# Computer Use 后续验收（2026-10-13）

本轮保留用户 VoiceOver 豁免。使用 mcp__cua_repl，启动/安装由公开 simctl 完成，实际界面点击、滚动和画面检查由 Computer Use 完成；未使用私有 HID 或更改宿主辅助权限。

## Watch 设置入口：实际缺陷及最小修复

旧 `.automatic` ToolbarItem 在40mm watchOS26.5的账号页面顶端没有可見 gear。采用唯一生产变化 `ToolbarItem(placement: .topBarTrailing)`，Watch专用增量构建成功，包 `/tmp/tokenpulse-watch-toolbar-ab.app`。新包中两语均出现右上 gear；实际点击进入设置，证明修改恢复了可操作入口。

- 英文：gear→Complication Settings，滚动到Complication Account→Choose Account，默认Claude有勾；选择DeepSeek后返回并显示DeepSeek wallet。重新进入确认DeepSeek的勾，选择Claude恢复；滚动到Exit Demo并点击，回到No Accounts。
- 中文：gear→表盘设置→表盘显示账号→选择账号，默认Claude有勾；选择DeepSeek返回显示“演示 · DeepSeek 钱包”；点击退出演示返回“没有账号”。
- 表盘系统验证前，以不带fixture参数的正常App启动并点击体验演示，选择真实标准演示账号Claude，未调用第三方服务。一次系统通知权限提示选择“不允许”，不影响本次表盘验收。
- 原生Crown点击正常回到系统表盘；长按表盘1.6秒确实进入系统切换器，工具获得系统表盘内部AX。Crown式滚动确实能切换到“新增”；进入图库→数据丰富→模块→获取。后续结果尚待记录。
- App横向drag未观察到切页，不记为通过；不因工具拖动证据不足修改TabView逻辑。

## 最终中文 iPhone 锁屏实际宿主：已通过

专用 DE11EC10-DE2C-4619-82E5-B60D7A06810B / iOS26.4 原最终包、壁纸与三个Claude组件均保留。经系统Settings→General→Language & Region→Add Language→简体中文→Use Chinese, Simplified切换真实系统语言，设置AX确认首选 zh-Hans-US（区域仍美国）；不是仅主App启动参数覆盖。

语言切换后SpringBoard一度无响应，仅重启该专用设备，没有清空状态。以不带fixture/语言override参数启动TokenPulse；实际点击体验演示，再展开Claude点击刷新。App AX确认同账号45%/80%/33%，下次重置更新为10/13/26 15:51，采集于2026年10月13日13:51。

使用模拟器侧键进入已有真实系统锁屏，Computer Use截图已实际查看：

- Inline 顶部为“13 周二 演示 · Claude 45%”，账号与45%完整。
- Circular Claude图标及45%完整。
- Rectangular “演示 · Claude”“5 小时额度”“下次重置10/13/26 15:51”与45%完整。

这是已保存WidgetKit实例的真实锁屏截图，不是主App渲染预览；更新的重置时刻与本次App刷新对应。原图在本轮Computer Use工具记录。未另存本地图片。本轮明确覆盖简体中文+美国区域组合，未更改区域为中国。

## Watch 实际表盘后续结果

“模块”获取完成后，使用其实际“添加”动作进入编辑器。选择中间复杂功能→所有App→TokenPulse→预览，确实放入矩形组件；选择左下区域→TokenPulse→预览，确实放入圆形组件。此款模块表盘的日期栏仅提供系统日期/关闭，不能据此假称已测试第三方Inline。

按Crown退出编辑、点击预览激活后，真实系统时间13:57的表盘上，矩形显示Claude图标、36%、中文5小时额度与下次重置；圆形显示Claude图标与36%。不是编辑器预览或主App模拟渲染。点击矩形打开TokenPulse；因为App此前停留在设置页，先保留该导航页，点返回后确实为Claude账号（54%），而非初始MiniMax。不能声称点击组件会自动清空现存导航栈。

## Watch 错误恢复与最大字号滚动

- error fixture en：实际看到橙色 Credentials have not synced or are no longer valid；点Refresh后错误消失，Remaining670、Collected at13:59。
- error fixture zh-Hans：实际看到橙色“凭证尚未同步或已失效”；点刷新后消失并显示剩余670和采集时间。
- long+最大辅助字号 en：从顶部用户原名“我的工作账号 / My very long Claude workspace Ω · 研究团队”分段滚动到底部“研究团队”，继续到额度、剩余/重置/采集时间和Refresh；点击按钮可操作，后续Sonnet33%显示。
- long+最大辅助字号 zh-Hans：同一用户原名未翻译或改写；实际滚动到5小时额度36%/剩余640，再到刷新；点击后截图显示Sonnet33%/剩余670，下一重置与采集时间变为14:00。
- 普通Crown按下回表盘、再次按下到应用列表，鼠标滚动可操作系统列表与表盘切换器。这证明Crown按钮和纵向滚动有输入，不代表App水平拖动已经通过。

## 当前剩余边界

1. App横向分页/触控swipe仍无可靠结果：Computer Use drag在系统表盘切换器和App都未观察到横移，不能确定是工具投递还是产品行为，不修改TabView掩盖问题。
2. Watch App完整内部AX树仍未取得；系统表盘/图库部分AX已取得，与App完整AX不同。VoiceOver已豁免。
3. Watch实际表盘目前新增证据为中文Circular/Rectangular；英文宿主、Corner/Inline和Smart Stack未在本轮实测。共享渲染器与既有测试证据仍单独保留。
4. Watch工具栏已由本轮最小生产修复恢复，两语实际导航验证通过；后续构建结果由08-toolbar-ab-evidence.md记录。

中文iPhone锁屏缺口已解除。08/09/10仍保留未覆盖边界，不假签全部完成。

## 收尾验证

- 14:03 再次返回真实系统模块表盘，圆形与矩形均已从36%更新到54%，重置时间也对应App的新快照；证明已保存组件可接收正常App发布的新数据。
- 工具栏修复的Watch专用Release无签名构建通过（`08-toolbar-final-release-build.log`），此前Debug签名构建通过；本轮未因单个UI位置变化重跑全部Provider业务测试。
- `git diff --check`通过。未提交、推送、安装真机或发布TestFlight。
- 当前独立Watch没有配对iPhone；其“设置→通用”未提供语言切换入口。本轮没有修改配对关系或用私有接口强制改变系统状态，因此不宣称英文Watch系统表盘验收完成。
- 模拟器保持可复查状态：专用Watch显示已配置中文模块表盘；DE11中文iPhone保留原锁屏组件。用户的其他模拟器未关闭或清空。
