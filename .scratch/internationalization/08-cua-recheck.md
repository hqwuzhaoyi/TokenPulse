# Computer Use 重试记录（2026-10-13）

本轮 `mcp__cua_repl` 重建后成功取得 Simulator AX 状态与截图，不再出现之前的 surfaces 配置错误。使用独立 TokenPulse i18n Watch（8FE5402A-2B44-4AB3-8A13-EF6E9279C33C，SE 3 40mm / watchOS 26.5）。从最终 `/tmp/tokenpulse-i18n-inline-native-final-signed.app` 内的 Watch 包升级安装；用公开 simctl 安装/启动现有隔离 Debug fixture，实际点击、滚动与截图全部通过 Computer Use。未使用私有 HID、AppleScript 或更改系统辅助权限。

## 已实际操作并观察

- Simulator 原生 Crown 点击从表盘切换到系统应用网格；切换列表显示也成功。
- 英文 empty fixture：通过鼠标滚动显露 Try Demo，点击后进入 Demo · Claude，5-Hour Quota 36%。滚动到底可看到 Remaining 760、Collected at 13:08 和 Refresh。点击 Refresh 后 Remaining 变为 670、Collected at 13:09；回顶部可看到45%。
- 中文 empty fixture：滚动显露“体验演示”，点击后进入“演示 · Claude”与“5 小时额度 36%”。滚动到“刷新”，点击后剩余760变为670。账号名称与中文标签正确。
- 英文 nous fixture：滚动过说明，实际点击 Start Authorization 后显示 TEST-CODE。Open Authorization Page 实际可点击（fixture的 openURL 处理器消费URL，不进行外部网络）；滚动可见等待状态与 Cancel，点击 Cancel 返回 Demo · Claude。
- 中文 nous fixture：实际点击“开始授权”后显示 TEST-CODE，滚动可见“打开授权页面”、原始 portal.nousresearch.com 域名和“等待授权”。点击打开按钮后，通过“取消”返回“演示 · Claude”。本轮没有保存真实凭证或进行真实服务登录。
- 以上截图由 Computer Use 返回并实际查看，原始图在本轮工具记录中；未另存为本地图片，也不把其他日期的截图算成本轮新证据。

## 尚未通过的边界

- Watch 内部未向该工具暴露完整 AX 树，只有 Simulator 窗口/Crown/Side/菜单；使用截图定位不能冒称完整内部 AX 验证。
- 水平 drag/scroll 未观察到账号分页切换，未计通过。表盘设置入口、账号选择与退出演示未完成。
- 实际表盘 complication 配置和宿主显示没有完成；大字号实际滚动及错误恢复仍需后续补验。
- 尝试打开中文锁屏专用 iPhone 的动态菜单时，多次出现 AXError.invalidUIElement；未完成切换，不计中文锁屏复验通过。
- 菜单弹出期间截图一度 unavailable，Cancel 后恢复；工具上下文偶发 inactive，重新 getApp 后恢复。不能据此归因产品缺陷。
- VoiceOver 仍按用户豁免，不测试、不声称通过。

本轮只新增部分实际交互证据，08/09/10不据此关闭；7/10完成数保持。未改产品源、提交或发布。独立 Watch 保留在中文示例账号页供后续继续。
