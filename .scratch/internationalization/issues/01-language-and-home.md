# 01: 语言基础与首页首条完整路径

**What to build:** 用户通过系统或应用语言选择，在简体中文和英文之间使用首页导航、空状态与示例账号；未支持的语言回退英文，语言变化不改变服务账号或额度数据。

**Blocked by:** None (can start immediately)

**Status:** complete

- [x] 接入原生翻译资源，支持 zh-Hans 与 en；主应用、Watch 和小组件目标均能打包所需资源，未支持的语言具有完整英文回退。
- [x] 首页导航、空状态、演示入口与至少一个示例服务账号的额度展示形成完整双语路径，示例数据能离线验收。
- [x] 语言和区域设置分开处理，跟随本设备有效设置；不增加自建语言选择器，不同步语言偏好覆盖其他设备。
- [x] 必要的前置整理先以兼容方式扩展展示能力，保留旧调用可用；不翻译身份字段或一次性迁移全部业务调用，后续各票可独立构建。
- [x] 确定共享术语规则：中文可保留 API Key、Token、OAuth、Provider 等常用英文术语，品牌名和模型名保持原文；操作、说明、错误提示使用所选语言。
- [x] 测试支持语言、英文回退及切换语言后示例账号身份、额度数值不变；验证导航可操作、VoiceOver 可理解、文字放大后不遮挡关键操作。
- [x] 完成主应用、Watch 和两端小组件构建，记录本票双语演示结果；仅代表本票路径完成，不宣称所有入口已翻译。

共同约束：首期仅简体中文与英文，复用现有展示/通知行为测试边界。常用英文术语不算漏翻译；不改变 Provider API、数据身份或授权架构，不自动翻译用户输入与第三方内容。每票完成自身范围的双语行为及可视验证，不能把质量检查全部留给最后一票。

## 实施与验证证据

- 原生 `TokenPulse/Resources/Localizable.xcstrings`，en 为开发语言，zh-Hans/en 打包到四个产品。`L10n` 仅适配现有共享字符串展示，语言不存储/同步，数字日期仍遵循区域。
- 从 ContentView 兼容提取 AddAccountView/QuotaViews，保持业务闭包、账号、窗口和 Codex 无预告隐藏条件。资源和 pbxproj 由负责人独占整合。
- `01-resources-final-build.log`：四产品无签名模拟器构建成功；`01-tests-final.log`：DemoMode 5测试、0失败，含 zh-Hans/en/fr 回退、原名/自定义名与身份/36%额度保持。
- `01-ui-en-parentheses.log`、`01-ui-en-large.log`、`01-ui-zh-large.log`：每轮真实运行1个 XCTest UI test、0失败；Home/Settings导航、展开示例额度、添加入口/取消、退出演示空状态和再次体验演示均点击验证。最大辅助字号 `accessibility-extra-extra-extra-large` 下关键操作可点击，正文换行/列表滚动；截图已导出并实际查看。
- `01-ui-en-attachments`、`01-ui-en-large-attachments`、`01-ui-zh-large-attachments` 含首页、详情、空状态；后两者另含真实 accessibility tree，额度 ProgressIndicator 分别为 `5-Hour Quota Used / 45% used` 与 `5 小时额度已用额度 / 45% 已用`。检查的是系统辅助功能标签和值，未宣称进行了语音听辨。
- 初始26.5模拟器启动/安装争用、独立26.4首启动迁移错误及UI同test二次启动等待均保留原日志；已停止自己的挂起命令并改独立单语言测试。无括号筛选的0测试轮次不计成功证据。未清除用户模拟器/账号；独立验收模拟器ID `776A1F40-1CF2-4F18-99C2-DAFE96899410`。

本票仅覆盖语言基础与首页离线示例路径，不表示授权、设置、通知和全部Provider展示已经翻译。
