# 最终 Corner/Rectangular 源验证（2026-10-13）

仅顺序执行下面四次xcodebuild，全部jobs1/非并行testing，复用已有cache。使用自有776A1F40-1CF2-4F18-99C2-DAFE96899410，未操作DE11/Watch/用户iPhone或rootGUI目标。root真实EN SmartStack已确认110 CNY/Wallet balance/Updated/账号完整并决定保留矩形修复；root随后完成中文各宿主，见09-watch-final-host-check.md；01—10已统一关闭。

```sh
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulse -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-build -jobs 1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > .scratch/internationalization/final-rect-four-target-debug-build.log 2>&1
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulse -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-release -jobs 1 CODE_SIGNING_ALLOWED=NO build > .scratch/internationalization/final-rect-four-target-release-build.log 2>&1
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulse -configuration Debug -destination 'platform=iOS Simulator,id=776A1F40-1CF2-4F18-99C2-DAFE96899410' -derivedDataPath /tmp/tokenpulse-i18n-build -jobs 1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO '-only-testing:TokenPulseTests/PlatformTests' '-only-testing:TokenPulseTests/WatchPresentationTests' test > .scratch/internationalization/final-rect-platform-watch-focused.log 2>&1
xcodebuild -project .scratch/internationalization/AcceptanceHarness/Acceptance.xcodeproj -scheme Acceptance -destination 'platform=iOS Simulator,id=776A1F40-1CF2-4F18-99C2-DAFE96899410' -derivedDataPath /tmp/tokenpulse-i18n-ui -jobs 1 CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO '-only-testing:Acceptance/WidgetRendererAcceptance/testEnglishRectangularWalletShowsAmountAndCurrency()' '-only-testing:Acceptance/WidgetRendererAcceptance/testChineseRectangularWalletShowsAmountAndCurrency()' test > .scratch/internationalization/final-rect-wallet-ocr-ui.log 2>&1
```

- Debug签名四产品 **BUILD SUCCEEDED**；Release无签名四产品 **BUILD SUCCEEDED**。Main Debug/Release均无额外Metadata.appintents；扩展metadata/resource原边界保留。
- Platform26+WatchPresentation3=29 tests/0fail，**TEST SUCCEEDED**。覆盖已有snapshot/selection/identity/date/独立授权与Watch本地refresh语义；未无因重跑831全量基线。
- 新rectangularWalletShowsAmountAndCurrency两语2UI/0fail，**TEST SUCCEEDED**；真正像素OCR两语均识别`1,234.56789012 USD`，不是仅AX assertion。附件`final-rect-wallet-ocr-ui/manifest.json`，负责人实际查看`68811522-3DA9-4B37-BCF3-6864730E696D.png`中文及`61019589-B8C0-4B26-BA74-435D2C26D4DF.png`英文，金额/货币完整，Wallet balance/钱包余额与更新时间完整，没有遗漏或新增零。OCR只要求金额和币种，中文其他文案仍实际图审；不声称OCR替代全部中文语义验收。
- 这2UI是原生shared renderer固定160×72尺寸，**不是Watch SmartStack/表盘真宿主**；root的真实Watch证据单独保留。
- 最新coverage脚本：681keys/14plural/387L10n calls/35动态域；catalog/format/literal/manual/source-location错误均0，四产品引用原共享catalog；`git diff --check`通过。

最终稳定签名iPhone包`/tmp/tokenpulse-i18n-rect-final-signed.app`（含最新Watch）。自有776冷启动bootstatus报DataMigrationFailed但状态Booted，实际29+2测试全部运行并通过；原环境日志`final-776-boot.log`保留，不把启动状态当产品失败或偷偷重启别的sim。没有提交/推送/发布，未测试实机或TestFlight。

root中文最终原范围真宿主已全部通过，见09-watch-final-host-check.md。最后2OCR/29focused进程均已exit0；仅自有776已shutdown减负，不动rootWatch/DE11或用户设备。09/10待root统一关闭，本代理未修改工单状态。
