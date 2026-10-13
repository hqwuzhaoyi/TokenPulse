# Watch Corner 宿主最小 A/B

root真实Infograph英文系统表盘发现：原主内容ProviderIcon只有icon/弧线/点，没有45%数字；Gauge currentValueLabel不构成该实际宿主数值显示证明。原失败保留，shared renderer不能代替。

仅改`TokenPulseWidgets/QuotaWidgetContent.swift`的watchOS accessoryCorner有metric分支：主内容用原`metric.valueText`（16pt rounded bold、monospacedDigit、lineLimit1、minScale0.5、tightening）。原widgetLabel Gauge及无fraction文本、状态overlay、fullAX和无metric分支不动；没有新key、精度舍入、货币/账号ID/snapshot改动。

```sh
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulseWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-build -jobs 1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > .scratch/internationalization/09-corner-ab-build.log 2>&1
ditto /tmp/tokenpulse-i18n-build/Build/Products/Debug-watchsimulator/TokenPulseWatch.app /tmp/tokenpulse-watch-corner-ab.app
```

BUILD SUCCEEDED，仅Watch app和Watch widgets。候选`/tmp/tokenpulse-watch-corner-ab.app`已独立复制，待root真实宿主A/B验收，不提前宣称已修复/保留。不安装、启动或操作任何模拟器，无GUI/新测试/广泛重构，不关闭08/09/10。
