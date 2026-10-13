# 09 共享原生 renderer 图审（负责人）

首轮 `09-shared-renderer-ui.log` 26 UI/0 fail；这是主 App 中复用生产 SwiftUI renderer 的固定 family 尺寸，不能替代真实 WidgetKit extension 或 Watch 钟面宿主。

负责人实际查看两语共 12 张：large quota、large longName、small wallet、circular quota、rectangular dateOnly、inline quota。Large 数值、1/0/3 个重置数量、wallet 1,234.56789012 USD 和 circular 63% 可见。dateOnly 显示日期而没有人为补午夜；更新 footer 为独立采集时间。LongName 可见省略，但原名称和完整 AX 保留。Inline 尾部重置数量单位省略，不能以 AX 完整算可视通过。

首轮 standalone 缺少真实 home-screen WidgetKit 的 content margin，边缘 Provider/footer 受圆角裁切；只在 DEBUG 包装补 16pt margin，再验真实尺寸。生产 WidgetKit 宿主不重复添加 margin。代理另审 14 张记录见 `09-renderer-edge-review.md`，发现 small exhausted 标题与 continuous timing 截断。

最小修复已冻结：small 标题缩放/紧排，continuous 复用完整短原生说明，inline 水平 ViewThatFits 保留完整 value/unit/重置数量，原 account 原文不改写，完整 AX 不变。最终 native renderer 全矩阵与真实 extension 宿主正在复验；此记录不提前宣称最终 fit 通过。

## 最终 fit 包第二轮真实图审

`09-fit-renderer-final-ui.log` 26 UI/0fail TEST SUCCEEDED，附件 `09-fit-renderer-final-ui/manifest.json`。负责人实际查看上述全部12张新图。Inline 两语当前完整显示 63%、↺1 reset / 1次；large 的四行数值、0/1/3 reset、更新与下次重置说明完整，长用户原文依旧仅可视省略，未重写。Circular 63%与rectangular date-only完整，未增加午夜。16pt margin后所有这些边缘Provider/footer完整。

**发现并保留未通过：** Small wallet在真实content margin后金额变为1,234.5678901…且USD不可见，两语同样问题。已交09源负责人做仅文字缩放/紧排的最小修复；不降低Decimal精度、不吞货币、不用AX完整替代可视验收。其他10张通过，wallet两张待再次复验。

## wallet / exhausted 最终恢复

`09-wallet-footer-final-ui.log` 10 UI/0fail TEST SUCCEEDED；负责人实际查看4张最终wallet/exhausted两语截图（manifest位于同名导出目录）。wallet原金额完整显示 `1,234.56789012 USD`，没有省略、小数舍弃或货币丢失。Exhausted前独立title行完整 `Weekly usage` / `每周已用`，Exhausted / 已用尽完整；重置日期、1reset/1次和Updated/更新于完整。4张最终可视通过，原失败图保留。其余footer相关6张由05独立图审。

单Text inline宿主兼容修正后 `09-inline-native-renderer-final-ui.log` 两语2UI/0fail。负责人实际查看2张最终图，完整63%与↺1次/1reset，原name原文完整、无省略；这是共享renderer证据，真实宿主复验另记。
