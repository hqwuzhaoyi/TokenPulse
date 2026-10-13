# 09 共享原生渲染器：边界场景实际图审

日期：2026-10-12。本代理已通过 `view_image` 实际逐张查看以下14张PNG（7场景 × en/zh-Hans），并读取对应14份原生AX文本树。文件映射依据 `09-renderer-ui/manifest.json`；没有构建、启动UI测试或修改源文件。

**证据范围是共享renderer在应用内原生固定frame中的展示。不是实际Widget/Watch扩展、系统桌面放置或timeline/runtime验收；这些由02代理负责。** 26项UI零失败只能证明测试路径运行，不能覆盖目视裁切。本代理没有查看负责人分配给自己的其余12张图。

## 实际结果

| 场景 | 实际查看图片 | 观察 |
| --- | --- | --- |
| small empty | [EN 1EEA8F4B](09-renderer-ui/1EEA8F4B-9052-45F4-B8CA-9F8E09A6B476.png)、[ZH A13C1C5A](09-renderer-ui/A13C1C5A-C301-481F-AF6F-C43990B9CE88.png) | 画面与AX分别为 `Add an account first` / “请先添加账号”，在small黑色固定框架中完整居中。没有数字、额度或余额零值。 |
| medium unselected | [EN F16ED690](09-renderer-ui/F16ED690-D719-4B4D-9937-75171C2C19EB.png)、[ZH 7984A44F](09-renderer-ui/7984A44F-A891-4928-8280-36F424773FB5.png) | 画面与AX分别为 `Choose an account to display` / “请选择展示账号”，medium完整居中；英文长度仍适配。未伪造已选账号或数据。 |
| small missing | [EN AD1C6159](09-renderer-ui/AD1C6159-967E-42C1-9AE4-7357867C3493.png)、[ZH E8E9FFA6](09-renderer-ui/E8E9FFA6-9466-46A8-8DA6-46FE2F94A205.png) | 英文 `The selected account has not synced yet` 分成两行完整可读，中文“所选账号尚未同步”完整。没有用0%或0余额替代缺失配置。 |
| small stale | [EN 1B6BC69B](09-renderer-ui/1B6BC69B-B980-4D18-AD1F-1B86FDF99639.png)、[ZH 476C2FB5](09-renderer-ui/476C2FB5-48A2-49FB-B726-E96A74A5F5B1.png) | 两语保留 `Fixture 1` 与63%旧读数，AX有 `Refresh failed · Previous data retained` / “刷新失败 · 保留旧数据”。英文橙色页脚画面无法显示完整结尾，图标与底部左右文字贴圆角边界并有裁切；语义存在但不能判可视通过。 |
| small replenishment | [EN F4D66830](09-renderer-ui/F4D66830-9AEE-4BE5-A9FE-E6C805A4ED27.png)、[ZH BCFF7ECD](09-renderer-ui/BCFF7ECD-F7F4-4081-861E-793984656547.png) | 中文画面“额度补充 持续补充”完整；英文画面只有 `Allowance replenishment Co...`，完整 `Continuous replenishment` 不可见。AX完整为 `Allowance replenishment Continuous replenishment`。没有将持续补充变成一个虚构重置时间；但英文的关键说明可视不完整。页脚有边角裁切。 |
| small dateOnly | [EN 55A8D8DE](09-renderer-ui/55A8D8DE-6CA1-4B7A-BB13-BA46DC560327.png)、[ZH 9917E9FD](09-renderer-ui/9917E9FD-1DFC-4E4A-AC4E-C895F571CFF8.png) | 两语重置行完整显示 `2026-10-14`，分别为 `Next Reset 2026-10-14` / “下次重置 2026-10-14”，该行没有clock、00:00或额外时区时间。页脚 `Updated 02:52` / “更新于2:50”是独立采集时间，不能误判为给重置日期补午夜；页脚末端仍有圆角裁切。 |
| small exhausted | [EN F072CE8A](09-renderer-ui/F072CE8A-B6FB-44F3-9095-E5E8646561E4.png)、[ZH D1E51562](09-renderer-ui/D1E51562-1525-4CDF-99D5-E16165264718.png) | `Exhausted` / “已用尽”明确可见、进度条满格，无0%或可用余额0推测。英文 `Weekly usage` 被值挤窄，拆词换行并省略，画面近似 `Weekl / y us...`；中文“每周已用”完整。两语时间是实际instant，允许含clock，与dateOnly不同。页脚/顶边有圆角裁切。 |

## 可视问题

1. populated small框架共性：顶部provider/更新图标贴圆角，底部“可重置1次”/`Available: 1 reset`和更新时间文字也贴圆角，部分字形/末尾时间可见裁切；英文stale状态尾句无法全部看到。
2. 英文small replenishment有可见省略，用户仅看到 `Allowance replenishment Co...`，不能完整读到continuous值。
3. 英文small exhausted把 `Weekly usage` 挤成拆词的两行省略，主状态Exhausted仍完整，但指标名可读性不通过。

这些问题已直接报告负责人。当前只确认native fixed-frame输出存在这些问题，不能据此断言系统扩展具有同样裁切；系统content margins/包裹环境需要其真实证据。也不能反过来用“系统可能有边距”将当前图直接算布局通过。

## 数据与语言边界

- empty/unselected/missing指导清楚，未将缺失数据映射成零。
- stale保留63%并有原生AX失败/旧数据说明，没有把缓存状态伪装成刷新成功。
- 两语言reset计数为 `Available: 1 reset` / “可重置1次”，英文单数正确；未伪造计数0。
- dateOnly的事件行没有clock/午夜，日期在这两图一致为2026-10-14；不能将独立更新时间误认为事件时刻。
- native AX中关键指导、失败信息与continuous字符串完整，证实语义字符串可查询；没有进行实际VoiceOver听辨，且AX完整不消除可视省略。
- 这14张没有钱包金额场景，不能据此宣称已验收货币零值/换汇或其余尺寸。未发现已查看范围中的造零、日期补午夜或将持续补充当精确重置时刻的问题。

## 已读取的原生AX树

- small empty English: [D39DFFB0-1A11-4A24-848D-625FF384C86A.txt](09-renderer-ui/D39DFFB0-1A11-4A24-848D-625FF384C86A.txt)
- small empty Chinese: [D0B9E877-5458-4894-8016-2C5B872A872D.txt](09-renderer-ui/D0B9E877-5458-4894-8016-2C5B872A872D.txt)
- medium unselected English: [3371A56D-EADF-44A3-B5FA-95D302743CB2.txt](09-renderer-ui/3371A56D-EADF-44A3-B5FA-95D302743CB2.txt)
- medium unselected Chinese: [B97800F4-2DD9-42A0-8DCB-C0FA149CCB19.txt](09-renderer-ui/B97800F4-2DD9-42A0-8DCB-C0FA149CCB19.txt)
- small missing English: [ECF20D31-3500-4510-83F5-38A2E7E768BB.txt](09-renderer-ui/ECF20D31-3500-4510-83F5-38A2E7E768BB.txt)
- small missing Chinese: [E07005D9-5633-440E-9E8B-8CB453E188CE.txt](09-renderer-ui/E07005D9-5633-440E-9E8B-8CB453E188CE.txt)
- small stale English: [30BB41E8-8A67-4C3E-BDFF-657CD2EA1017.txt](09-renderer-ui/30BB41E8-8A67-4C3E-BDFF-657CD2EA1017.txt)
- small stale Chinese: [743B1699-CB01-47CA-84B3-4951FE8FDECF.txt](09-renderer-ui/743B1699-CB01-47CA-84B3-4951FE8FDECF.txt)
- small replenishment English: [15118CD9-DDB4-442E-9BB1-E4B7919F4D03.txt](09-renderer-ui/15118CD9-DDB4-442E-9BB1-E4B7919F4D03.txt)
- small replenishment Chinese: [E7C7AB88-9511-4DCD-9228-ADBBAD402160.txt](09-renderer-ui/E7C7AB88-9511-4DCD-9228-ADBBAD402160.txt)
- small dateOnly English: [80A7324D-DCFF-4758-8A9B-7CF298938235.txt](09-renderer-ui/80A7324D-DCFF-4758-8A9B-7CF298938235.txt)
- small dateOnly Chinese: [AC654C46-B3FE-4494-9E88-52E1CFE9C1DC.txt](09-renderer-ui/AC654C46-B3FE-4494-9E88-52E1CFE9C1DC.txt)
- small exhausted English: [DDDA4CC1-B371-4F4A-998E-5AA1353C4A39.txt](09-renderer-ui/DDDA4CC1-B371-4F4A-998E-5AA1353C4A39.txt)
- small exhausted Chinese: [F40F9CDB-062C-4192-8CA4-19A135D834B3.txt](09-renderer-ui/F40F9CDB-062C-4192-8CA4-19A135D834B3.txt)


## 最终追加：09-fit-renderer-final-ui 实际图审

2026-10-12，在负责人导出完成后，本代理又通过 `view_image` 逐张实际查看上述7场景对应的新14张PNG，并读取新14份AX树。不是只看26项UI成功日志；本轮仍严格为**共享renderer原生固定frame/16pt host margin**，不是actual extension/runtime。原审查保留为历史，本段为最新结论。

| 场景 | 最新实际查看图片 | 本轮可见结果 |
| --- | --- | --- |
| small empty | [EN 1757515B](09-fit-renderer-final-ui/1757515B-61B5-483A-BCF3-3F77B3B7C028.png)、[ZH 6DEE2AF9](09-fit-renderer-final-ui/6DEE2AF9-EA5F-4483-AD2E-444B5FC739D9.png) | 两语言添加账号指导仍完整居中，无0值，无裁切。 |
| medium unselected | [EN DD3E453E](09-fit-renderer-final-ui/DD3E453E-0DEA-494B-8416-A7F984121BC5.png)、[ZH 0DB9D614](09-fit-renderer-final-ui/0DB9D614-8AFE-4121-8488-559440B43865.png) | 两语言选择展示账号指导完整，未伪造选择或数值。 |
| small missing | [EN B556C409](09-fit-renderer-final-ui/B556C409-09DC-4C9B-92FF-5DE5DAAE8558.png)、[ZH D5C52244](09-fit-renderer-final-ui/D5C52244-9225-4842-97A2-352A5E22F811.png) | 英文两行与中文单行均完整，边距后文字仍适配，不显示0%。 |
| small stale | [EN 8979C049](09-fit-renderer-final-ui/8979C049-132C-47CC-B458-84507FCA6C1B.png)、[ZH C4D5AD16](09-fit-renderer-final-ui/C4D5AD16-F94C-4B05-894C-A0DE2923C78E.png) | 63%及标题/图标完整，圆角剪字已消除。中文失败/旧数据页脚完整；英文橙色仅见 `Refresh fail...`，完整旧数据解释仍仅AX可读，未解决英文信息省略。 |
| small replenishment | [EN 402009FC](09-fit-renderer-final-ui/402009FC-36DA-4317-B50F-7A5C1B537A1D.png)、[ZH B90F8E67](09-fit-renderer-final-ui/B90F8E67-AEAA-4AF2-99A5-B22A547B5C3F.png) | 英文 `Continuous replenishment` 已两行完整显示，中文“持续补充”完整；旧的关键continuous省略已解决。英文Weekly/usage按词正常两行。英文更新时间仅见 `Updated 03...`，完整时间只在AX；中文更新时间完整。 |
| small dateOnly | [EN 8AF61E6B](09-fit-renderer-final-ui/8AF61E6B-B834-444B-A029-7876DAC2AF27.png)、[ZH CD8D16D5](09-fit-renderer-final-ui/CD8D16D5-48B5-40D7-AFAB-DFEBC2F9AB27.png) | 重置行仍完整为2026-10-14，两语言都没有clock/午夜，63%不变。中文footer时间完整；英文footer更新时间省略为 `Updated 03...`，不是重置日期增加时刻。 |
| small exhausted | [EN 643F2FFB](09-fit-renderer-final-ui/643F2FFB-AD7A-43C1-8C51-5FE316ECCEEA.png)、[ZH 30EE53E7](09-fit-renderer-final-ui/30EE53E7-C2A0-4303-A1C6-4A5D1473A43B.png) | Exhausted/已用尽值、满格条和下次重置instant完整；中文指标名完整。英文Weekly usage仍被挤到仅W/e残片；AX该label框宽只有7pt，可视问题未解决。英文更新时间仍省略，中文完整。 |

本轮确认：16pt边距使原先的圆角剪字消失，图标、账号名和重置计数全部离开遮罩边缘；持续补充的关键英文语义已经完整显示。empty/unselected/missing、63%旧值、1次单数和日期精度边界没有被破坏。

**仍不能把这14图全部判为完整可读：** 英文exhausted指标名受到严重压缩（最新AX宽7pt，标签虽完整仍看不出完整Weekly usage）；英文stale错误/保留旧数据以及部分英文更新时间有可见省略。最新AX中分别保留完整 `Refresh failed · Previous data retained`、`Updated 03:08/03:09`，但AX完整不等于画面完整。没有发现新的造零、日期补午夜或持续补充伪造精确重置事件问题。

已将残留可视问题直接反馈负责人。没有改产品/资源/测试、没有构建或操作模拟器，也没有替负责人审查其余12图或系统扩展。

### 本轮读取的14份AX树

- small empty English: [573F79C9-AB46-4E5D-A691-2306D2F0411F.txt](09-fit-renderer-final-ui/573F79C9-AB46-4E5D-A691-2306D2F0411F.txt)
- small empty Chinese: [B3EA4E7C-52C9-4F37-9164-330CE02EDB4F.txt](09-fit-renderer-final-ui/B3EA4E7C-52C9-4F37-9164-330CE02EDB4F.txt)
- medium unselected English: [EDC93CAA-C8DB-49AD-A847-8E6D069D65C7.txt](09-fit-renderer-final-ui/EDC93CAA-C8DB-49AD-A847-8E6D069D65C7.txt)
- medium unselected Chinese: [6490CDFB-8DFC-412D-B0B3-87C8C9A88023.txt](09-fit-renderer-final-ui/6490CDFB-8DFC-412D-B0B3-87C8C9A88023.txt)
- small missing English: [F75948FE-2A4F-4AFD-B775-3B389F8EDA02.txt](09-fit-renderer-final-ui/F75948FE-2A4F-4AFD-B775-3B389F8EDA02.txt)
- small missing Chinese: [9D0EE040-AC89-4A17-B0E1-3B00BC61778F.txt](09-fit-renderer-final-ui/9D0EE040-AC89-4A17-B0E1-3B00BC61778F.txt)
- small stale English: [8BFB0A41-E70F-472F-BF58-12A3D2A2CE2D.txt](09-fit-renderer-final-ui/8BFB0A41-E70F-472F-BF58-12A3D2A2CE2D.txt)
- small stale Chinese: [41655663-ADDD-45CB-9FF0-6B6DB851442E.txt](09-fit-renderer-final-ui/41655663-ADDD-45CB-9FF0-6B6DB851442E.txt)
- small replenishment English: [87032CEC-39AF-4914-A2A7-0FC2FCEE49A6.txt](09-fit-renderer-final-ui/87032CEC-39AF-4914-A2A7-0FC2FCEE49A6.txt)
- small replenishment Chinese: [3C5D5AC2-C9BF-4260-ACDD-A0E668B0AB3C.txt](09-fit-renderer-final-ui/3C5D5AC2-C9BF-4260-ACDD-A0E668B0AB3C.txt)
- small dateOnly English: [B278FB75-DD69-46E7-A09B-65B8289739D2.txt](09-fit-renderer-final-ui/B278FB75-DD69-46E7-A09B-65B8289739D2.txt)
- small dateOnly Chinese: [79D20F62-6B6B-4AAA-844C-986C95ED793B.txt](09-fit-renderer-final-ui/79D20F62-6B6B-4AAA-844C-986C95ED793B.txt)
- small exhausted English: [67574F53-16E5-4D06-873E-8CF2C1C394DA.txt](09-fit-renderer-final-ui/67574F53-16E5-4D06-873E-8CF2C1C394DA.txt)
- small exhausted Chinese: [AAEE3FB9-8A8D-4E41-A445-B27DC5944CDF.txt](09-fit-renderer-final-ui/AAEE3FB9-8A8D-4E41-A445-B27DC5944CDF.txt)


## 最终追加：09-wallet-footer-final-ui 六图复核

2026-10-12，已再次通过 `view_image` 实际看完stale/dateOnly/replenishment两语言的新6张PNG，并读完对应6份AX树。仍仅共享renderer原生fixed-frame/host margin可视审查，不是actual Widget/Watch extension或系统runtime验收。wallet/exhausted的新4张由负责人审，本代理未查看，不替其判定。

| 场景 | 最新实际查看截图 | 最终可见结果 |
| --- | --- | --- |
| SmallStale | [EN D6AB1838](09-wallet-footer-final-ui/D6AB1838-DD9D-4DE8-9840-B596A848F331.png)、[ZH FE9BB3A5](09-wallet-footer-final-ui/FE9BB3A5-63A5-4CE0-917D-C6E7094AF9DC.png) | 英文橙色完整显示 `Refresh failed · Previous data retained`，自然两行，无省略；中文失败/保留旧数据指导也完整。63%旧读数、Fixture 1和可重置1次保留，没有刷新成功伪装。 |
| SmallDateOnly | [EN CF1162DD](09-wallet-footer-final-ui/CF1162DD-672E-4DCC-87D1-D93B761BFB16.png)、[ZH 65C08DCD](09-wallet-footer-final-ui/65C08DCD-3AB2-4797-9A8B-567D942251C6.png) | 两语言重置事件行完整为2026-10-14，没有clock/午夜；独立footer完整为 `Updated 03:15` / “更新于3:15”，没有省略或给事件日期添加时刻。 |
| SmallReplenishment | [EN 9EBEF84D](09-wallet-footer-final-ui/9EBEF84D-4666-4C9A-9266-CA9EA4CCFBF0.png)、[ZH 51F281FD](09-wallet-footer-final-ui/51F281FD-5467-4D45-A28D-BFC3E9F3427A.png) | 英文 `Continuous replenishment` 两行全部可读，中文“持续补充”完整；独立更新时间为 `Updated 03:16` / “更新于3:15”，完整可见，未把补充写成精确重置。 |

**本轮所审6图可视通过。** 原来stale英文尾句与更新时间省略已解决；标题、状态、进度、重置计数及底部时间/错误说明在圆角内完整可读，没有新重叠、边缘剪字、断词残片或关键文本省略。英文Weekly usage以正常单词换行，连续补充说明正常两行。日期精度、旧数据标识、63%读数和单数1次保持正确。

这一结论关闭本审查中stale/dateOnly/replenishment的相应旧可视问题；已用尽及钱包最新结论应由负责人看完对应4图后另记。没有改source或重跑UI/构建。

本輪读取的AX树：

- SmallStale English: [B8570CF3-7D44-4B9D-BED3-34A153854153.txt](09-wallet-footer-final-ui/B8570CF3-7D44-4B9D-BED3-34A153854153.txt)
- SmallStale Chinese: [4909899B-D330-4C0E-8023-A7DEEBCB5743.txt](09-wallet-footer-final-ui/4909899B-D330-4C0E-8023-A7DEEBCB5743.txt)
- SmallDateOnly English: [79326022-442E-407E-B8D2-5F1930FB6CC3.txt](09-wallet-footer-final-ui/79326022-442E-407E-B8D2-5F1930FB6CC3.txt)
- SmallDateOnly Chinese: [3BF87841-1A01-4FC8-9B3C-CCFAA4AE2E5D.txt](09-wallet-footer-final-ui/3BF87841-1A01-4FC8-9B3C-CCFAA4AE2E5D.txt)
- SmallReplenishment English: [901E15FF-8A1D-4B24-B32D-AF1C88A3073C.txt](09-wallet-footer-final-ui/901E15FF-8A1D-4B24-B32D-AF1C88A3073C.txt)
- SmallReplenishment Chinese: [F96936DE-24DE-4C32-BA40-DEFBD25A0E5B.txt](09-wallet-footer-final-ui/F96936DE-24DE-4C32-BA40-DEFBD25A0E5B.txt)
