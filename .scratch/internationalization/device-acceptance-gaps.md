## 最终范围与边界（2026-10-13）

原定国际化验收已完成，10/10关闭。中文iPhone锁屏、Watch两语四种family与SmartStack真宿主及普通触控/滚动等已由Computer Use补验；旧“全部Watch输入/中文锁屏未验”清单仅作为历史，不再是阻塞。

VoiceOver实际听辨/语音导航由用户明确豁免。水平swipe未取得可靠工具投递结果、完整Watch App内部AX树无法导出继续记录为未测工具边界，不称通过；它们不是原票逐种手势/整树交付要求。用户实机未测试，本轮验收是模拟器结果。

最新证据见 [最终Watch真宿主](09-watch-final-host-check.md)、[最后验证](final-rect-validation.md) 和 [验收汇总](10-final-acceptance-summary.md)。以下内容是逐步消除缺口的历史记录。

## 最新收敛（2026-10-13 14:02）

中文iPhone锁屏已实际复验，Watch两语设置与选择账号/退出、错误恢复、大字号纵向滚动已补齐；中文模块表盘Circular/Rectangular真宿主已验证。旧“所有Watch输入/中文锁屏未验”描述已被这些新证据取代。仍缺App水平分页、完整内部AX与Watch英文/其他形状宿主；VoiceOver按用户豁免。详见 [续验记录](08-09-cua-continuation.md)。以下保留历史清单以追溯，不能作为最新未验列表。

## Computer Use 已部分恢复（2026-10-13）

本轮补验 Watch 两语空状态→演示、滚动→刷新、两语设备码授权开始/打开（无网络fixture）/取消返回，均实际点击并查看结果。详情见 [重试记录](08-cua-recheck.md)。分页/设置/表盘、完整内部AX和中文锁屏仍未通过，VoiceOver继续豁免。当前仍7/10 complete；以下历史“完全无触控能力”描述被本轮证据部分更新，不能视为最新状态。

# 设备验收缺口

**2026-10-13 范围更新：** 2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。

这里只记录尚未实际完成的设备操作，不替代已保存的行为、native UI、截图或 AX 证据。未测试实机或 TestFlight。

## iPhone VoiceOver 听辨（用户已豁免）

代码、两语原生 AX 字段、长文字与最大辅助字号已有证据；没有开启 VoiceOver 后实际听辨与语音导航录音。使用演示账号即可，无须输入真实秘密。

1. 在设备的辅助功能设置开启 VoiceOver，再打开 TokenPulse 演示模式。
2. 在中文、英文下分别导航 Provider 选择：听搜索提示、节索引、品牌名称和已选状态。
3. 听添加页的账号名、API Key、地区/网关字段及保存、取消；用户输入与品牌应保持原文。
4. 听额度卡片的已用/剩余、货币或技术单位、日期-only 重置、刷新状态；未知数值不能听为零。
5. 听账号设置开关和删除确认说明，取消后账号仍在。
6. 记录实际读出的词、遗漏、错误单位或无法聚焦控件；关闭 VoiceOver 恢复原设置。

## Watch 真实触控与滚动

小屏 Watch 两语原生截图、最大辅助字号、Gauge、错误 footer、授权码完整单行均已查看。没有实际完成 tap、Digital Crown、swipe/scroll、完整 AX 树和 VoiceOver 听辨。现有工具没有原生 Watch 输入能力；失败 HID 尝试未计为成功，未改系统辅助权限。

在 `.scratch/internationalization/08-ui/README.md` 的隔离 fixture 或演示模式中：

1. 空页滚动到“体验演示 / Try Demo”，点击进入；用 Crown/滑动浏览账号。
2. 点击一个账号，滚动长名称和额度详情，点击刷新，检查更新时间与失败恢复说明。
3. 查看独立 Nous 授权页，点击开始，等待模拟代码；大字号下完整读取代码。
4. 点击复制/打开授权页与取消，确认原始代码、host、账号身份没有被语言改写。
5. 原 VoiceOver 听辨步骤已由用户豁免，不再作为本轮验收门槛。

iPhone/Watch 不必使用相同语言。Watch 保持设备本地授权与查询，没有增加手机代查或新管理入口。

## Watch 表盘组件实际宿主

共享 native renderer 与行为验证不能替代表盘宿主。实际表盘安装、选择本机关注账号、circular/rectangular/inline 展示与 VoiceOver 尚无执行证据，需在 Watch 系统宿主按各形状检查；日期-only 不应补午夜，未知数值不应变零。iPhone WidgetKit extension 的真实 snapshot/timeline、配置与跨语 ID 证据单独保存在09报告。

## 最后实际 iPhone WidgetKit 宿主范围

最终 signed包原contexts上EN锁屏circle/rectangular/inline真实显示已通过，normalSmall三指标45/80/33%完整。中文正常主屏绑定及同包ZH→EN→ZH已通过，两语shared native renderer全部已查看；最终中文锁屏未独立重验，因此不记两语所有family真宿主完成。极小circle在未配置时提示可视省略但AX完整、没有造0；绑定Claude后45%与图标完整。

最终包 `/tmp/tokenpulse-i18n-inline-native-final-signed.app`；构建与资料来源见 `09-evidence.md`。这些已完成的iPhone结果不能替代实际Watch钟面，也不能替代VoiceOver真实听辨。
