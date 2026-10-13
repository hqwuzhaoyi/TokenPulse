# Rectangular/Smart Stack 金额遗漏最小 A/B

root在英文40mm真实Smart Stack复现：Claude45%环有值但account/window标题省略；正常App切DeepSeek钱包、selectedID9与timeline确认后，宿主只有icon/CNY/Wallet balance而没有金额。原AX有完整金额，不能替代可视输出。

仅改`accessoryRectangular`：wallet/no-window不再为外部icon占48pt，改纵向显式原metric.valueText（14pt rounded bold、monospaced、line1/minScale.5/tightening/priority1），保留displayTitle区分monetary余额/非货币单位，附完整原状态。quota分支保持ring/数值、account .6及title .65缩放/tightening。fullAX、snapshot、ID/API、币种与Decimal不改，无新key；Corner已实际验证修复保留。

```sh
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulseWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-build -jobs 1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > .scratch/internationalization/09-rect-ab-build.log 2>&1
ditto /tmp/tokenpulse-i18n-build/Build/Products/Debug-watchsimulator/TokenPulseWatch.app /tmp/tokenpulse-watch-rect-ab.app
```

BUILD SUCCEEDED。独立候选已复制/tmp/tokenpulse-watch-rect-ab.app，待root实际宿主确认，未提前判修复保留/09complete。

## 有意义回归测试（已写，未执行）

scratch `AcceptanceHarness/WidgetRendererAcceptance.swift`增加两语rectangularWalletShowsAmountAndCurrency。现有USD长Decimal钱包fixture复用，不创建新生产逻辑。测试用Vision OCR识别真实原生截图像素并断言完整`1,234.56789012 USD`（忽略空白/分组逗号），保留原图与OCR证据；不会仅看AX summary而漏掉实际画面缺金额。旧分支没有金额像素应失败，完整精度或USD可视丢失也不能通过。

仅Swift语法parse已通过；未编译/运行新UI test，不冒称结果绿。root仍使用Simulator，故本代理没有GUI、安装、启动/操作模拟器或新测试执行。实际WidgetKit/SmartStack宿主仍以root真图判定。

## 最终验证更新

root真实EN SmartStack非编辑模式确认同context钱包110CNY、Demo · DeepSeek wallet、Wallet balance/Updated完整，保留最小修。随后最新四产品Debug/Release构建、Platform26+WatchPresentation3=29/0fail、新两语OCR可视2UI/0fail与两图实际审查已完成；命令/实际范围见final-rect-validation.md。最初parse-only未执行记录为历史，不代表本次最终结果。中文真实宿主待root，无擅自关闭09/10。
