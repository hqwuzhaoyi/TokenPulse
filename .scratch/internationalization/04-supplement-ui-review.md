# 04 补漏截图实际可视审查

审查日期：2026-10-12。只读取已导出资源，通过 `view_image` 逐张查看下列10张PNG；没有构建、启动UI测试或修改产品、翻译、测试代码。

文件与场景名称已对照 `04-supplement-ui/manifest.json` 和 `/tmp/tokenpulse-supp-ui-export.log`。结论仅限实际看见的这10张画面，不把其他测试通过或未查看截图视为本次目视验收。

## 逐场景结果

| 场景 | 已实际查看的英文/中文截图 | 看到的内容与判断 |
| --- | --- | --- |
| modelNames | [英文8E24](04-supplement-ui/8E24A3AD-DE7A-43B0-B3B0-9BC9317F07C5.png)、[中文621A](04-supplement-ui/621A8076-5FF3-4E38-909F-3603BDC0A1F0.png) | 英文两行分别保留原始“原始模型（未启用）”，第二行仅为应用追加状态显示 `(disabled)`；`Details` 和中文“详情”分别对应当前语言。中文第二行出现两份“（未启用）”，一份属于原名、一份属于应用状态；这是保留原名的预期结果，不应为消除重复而删除原名。两行与分隔线完整，未见截断。 |
| ownedScope | [英文E928](04-supplement-ui/E9287274-3954-4554-BD68-7A2AC8FB24B9.png)、[中文237D](04-supplement-ui/237D8273-0584-4D45-9051-74D5B7C202C8.png) | 英文范围为 `Team · Original target 原文 · Shared`，中文为“团队 · Original target 原文 · 共享”。`Original target 原文` 在两语言中保持原文，应用的团队/共享组成部分正确翻译。英文 `Monthly monitoring budget Details` 与中文“每月监控预算详情”可读；已用1 USD、剩余9 USD、预算10 USD仍各自明确。长范围一行全部可见，没有省略号或与左侧标签重叠。 |
| payAsYouGo | [英文12D63](04-supplement-ui/12D63B72-94F7-41BA-BDD2-5FEC8073AC3B.png)、[中文40D](04-supplement-ui/40D6801F-E81C-4EDB-9BF0-6136947E72CB.png) | `Original account 原文` 两语言完全保留。套餐说明分别为 `DevPass · Pay-as-you-go` 与“DevPass · 按量计费”。英文 `Key lifetime limit`、`Allowance type`、`No periodic reset` 与中文“Key 累计限额”“额度类型”“无周期重置”符合限额/非周期语义；9 / 10 USD credits显示完整，未呈现为现金钱包。 |
| teamPlan | [英文CE9A](04-supplement-ui/CE9A944A-0891-4619-91C0-D413A6D685E3.png)、[中文B615](04-supplement-ui/B6159D81-9F17-4710-A027-35B1435B39F7.png) | `Original account 原文` 保留；英文副标题 `xAI API · Team original-team-原文`，中文副标题“xAI API · 团队 original-team-原文”，原始团队标识 `original-team-原文` 没有被翻译。余额说明分别为 `Posted prepaid balance` 与“已入账预付余额”，12.34 USD不变且明确；品牌、行尾导航箭头和文字均可见。 |
| unknownUnits | [英文F7CC](04-supplement-ui/F7CC7CB0-1B1B-4145-B9E4-D4985533A1F2.png)、[中文5B61](04-supplement-ui/5B619C1C-6DA6-4B33-880B-142BEE24B021.png) | `Original model 原文` 保留。英文为 `Remaining` + `1 unit (type not provided)`，中文为“剩余” + “1 单位（类型未提供）”。单数英文准确；没有货币符号、USD或Token推测。完整说明适配当前宽度，没有被裁切或压到左侧标签。 |

## 整体可读性与问题

这10张图中，标题、取消操作、范围、套餐副标题及相关数值均处于可见区域；没有发现省略号、重叠、横向裁切或重要文字被卡片边缘遮挡。英文文字扩张在这些实际截图里仍完整可读，中文的常用品牌/API/Key/credits/标识保持合理原文边界。

未发现需要修改的可视问题。原始模型名包含中文状态词、原始target/account/team含中文字符属于本次验证的保留边界，不作为英文漏译。

本次没有查看 characters、hours 或 manusRefill 场景，也没有执行VoiceOver听辨、触控或额外字号/设备验收；这些不能由当前10张静态截图代替。characters的旧locator问题由负责人另行重验，本文件不把它判成产品显示错误或已通过。
