# Watch 最终系统宿主验收（2026-10-13）

仅使用专用 Watch 8FE5402A-2B44-4AB3-8A13-EF6E9279C33C（SE 3 40mm / watchOS 26.5）。保留实际演示账号、App Group、表盘与智能叠放实例。Xcode公开simctl准备系统语言/重启/安装；所有实际点击、滚动、表盘选择和截图检查通过 mcp__cua_repl。不是主App渲染预览，也未调用私有HID。图片在本轮工具记录，未另存截图文件。

## 英文系统语言与既有实例

原系统AppleLanguages=[zh-Hans-CN]、AppleLocale=zh_CN，临时改为en/en_US后重启，正常启动不带fixture或App语言覆盖的TokenPulse。实际App与系统菜单变为英文。

- 原Modular表盘Rectangular显示Demo·Claude / 5-Hour Quota / Needs Update，准确反映旧快照已跨过重置边界。点击组件进入Claude后返回，真实表盘更新为45%与Next Reset 10/13/26 20:35，Circular同为45%。
- 系统Add new face→Data Rich→Infograph→Get→Add，编辑左上Corner选择TokenPulse并保存激活。旧代码真实宿主只有品牌图标+弧线/白点，没有数值，保留失败。
- 系统Astronomy→Solar Graph→Get→Add，编辑底部Inline选择TokenPulse并保存激活。实际clock18:41时底部完整显示DEMO · CLAUDE 63%，不是只看编辑器预览。
- 从真实表盘滚动进入Smart Stack，Edit→+→TokenPulse→Done，实际正常Stack可显示并点击打开账号。

## Corner 最小修复与真宿主结果

旧外层ProviderIcon保留在角落，Gauge currentValueLabel被宿主忽略。最小改为外层直接显示原metric.valueText（16pt、单行、允许缩放），保留widgetLabel Gauge、无数值语义和完整AX。

安装 `/tmp/tokenpulse-watch-corner-ab.app` 并正常启动App发布后，切回并激活Infograph，实际左上显示45%文字+弧线，数字恢复。切换正常App表盘选择到DeepSeek钱包（只读核对选择ID为DE...009）后，Pixel Accurate真宿主主文本110 CNY完整；弧线标签保留CNY 110 CNY。未改金额、币种、ID或快照。

## Smart Stack 真实缺陷与最小修复

原40mm英文quota账号名与“5-Hour Quota”被截断。切到DeepSeek钱包后真实Stack只显示DeepSeek图标、CNY和Wallet balance，没有金额；Pixel Accurate截图确认金额确实缺失，而非分辨率问题。

最小Rectangular修改：钱包或无窗口的余额用原valueText明确展示金额，保留displayTitle、完整状态；标题与账号名单行缩放/tightening。没有新翻译key，未改Decimal、币种、API、ID、快照或提醒逻辑。

安装 `/tmp/tokenpulse-watch-rect-ab.app` 后保持原Stack实例，经一次系统Edit→Done重新显示新snapshot（未删除实例）：

- EN正常Stack完整显示“Demo · DeepSeek wallet”“110 CNY”“Wallet balance”“Updated 18:51”。
- 通过正常App设置选择Claude，返回Stack后Edit→Done；实际完整显示“Demo · Claude”“5-Hour Quota”、54%、Next Reset 10/13/26 20:53，无先前标题省略。

以上都是离开编辑模式后的真实系统宿主结果，AX单独包含金额不能替代本次像素观察。

## 中文还原与剩余记录

英文检查后恢复原系统zh-Hans-CN / zh_CN并只重启此专用Watch。中文Corner/Inline/SmartStack复验结果待后续追加；最终构建与回归由负责人串行执行，不能提前记绿。

## 中文最终真宿主已通过

恢复原zh-Hans-CN / zh_CN后重启并正常启动App，无fixture或语言参数覆盖。所有已添加表盘、Smart Stack实例和标准演示选择均保留。

- Infograph真实系统表盘左上明确显示54%与弧线，Corner数字没有因换语言丢失。
- Solar Graph实际激活后底部完整显示“演示 · CLAUDE 45%”；图库预览曾短暂显示旧英文，但实际激活的系统宿主已为中文，不混记缓存预览为结果。
- Modular实际clock18:57：矩形完整“演示 · Claude”“5 小时额度”“下次重置2026/10/13 20:55”和45%；圆形Claude图标/45%。
- 正常中文Smart Stack：完整“演示 · Claude”“5 小时额度”、54%与两行重置时间。
- 通过正常App表盘设置切到DeepSeek钱包，原Smart Stack经Edit→Done后，实际正常非编辑页面完整显示“演示 · DeepSeek 钱包”“110 CNY”“钱包余额”“更新于18:58”。
- 返回已保存Modular真实表盘，矩形同样显示完整110 CNY、钱包余额、更新时间；圆形显示DeepSeek图标和110 CNY。原金额、货币与账号均保持。

本轮支持的四种Watch family均有两种系统语言的真实宿主证据（Circular/Rectangular/Corner/Inline），Smart Stack亦有两语正常显示与可打开账号证据。首轮发现的Corner丢数值、Rectangular钱包缺金额及英文标题截断均已通过新包真宿主纠正。英文Corner另有110 CNY长于百分比的原生显示，矩形钱包新增长Decimal OCR回归由负责人最终执行。

系统仍按预算调度widget重载，短暂旧快照未被假称即时更新。部分过渡通过进入/退出系统编辑重现正常新快照；没有删除重建账号，也没有伪造timeline数据。VoiceOver按照用户豁免，未称已听辨。水平swipe工具未测的限制归08记录，不是原票逐种手势门槛。
