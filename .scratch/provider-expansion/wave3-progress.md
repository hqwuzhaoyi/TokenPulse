# Sol 第三批执行记录

用户继续授权实施，基线b322f5c（46个provider，465项测试通过），当前文档快照0477a43。全部25个第三批接入已整合，71个provider和62张integration均按完整实现+图标存在规则done；7张研究未完成。真实账号和物理设备保留未验证事实，不作为接入关票门槛。

| 工作者 | 票号 |
| --- | --- |
| sol_gateway | 13, 14, 15, 37 |
| sol_regional | 41, 42, 43, 47 |
| sol_web | 44, 48, 62 |
| sol_copilot | 46, 58, 61 |
| sol_research | 49, 54, 55 |
| sol_wallet | 45, 50, 51 |
| root | 52, 53, 56, 57, 59 |

第三批先领取24张已解锁票；44 Devin实现且图标存在后继续62 Windsurf，共25张实施票。7张可行性研究票保持独立范围，不以添加枚举或图标冒充可用接入。

公共网页登录使用临时WK会话，按固定origin提取明确字段，并显式选择组织/工作区。凭证绑定provider、账户UUID、origin与工作区，刷新前复核。root统一串行执行XCTest和多目标构建，工作者不启动Xcode或模拟器。

表中各组全部交付已整合。root完成52 Qwen/53 Raycast/56 T3/57 TypeSafe/59 ZoomMate；research完成49 Mistral/54 Replicate/55 Sakana（57在实现前转给root）。44 Devin完成后62 Windsurf继续并完成，原依赖关系保留溯源，未替换成真实授权通过声明。

## 自动验证与图标验收

- 公共框架/局部整合的473项、Qwen等9项定向测试属于历史中间结果。71入口完整XCTest已实际执行607项、0 failures，日志 `/tmp/tokenpulse-wave3-all71-v2.log`、结果包 `/tmp/tokenpulse-wave3-all71-v2.xcresult`。
- unsigned71多目标构建正在root串行执行，结果待root记录，不能用旧46入口build推作本轮通过。
- root实查71图标无缺失，56资产映射使用53个image sets，15 SF映射使用8个已存在的系统符号；18个通用图标明确标注，见[icon-acceptance](icon-acceptance.md)。当前25票Status统一done/current gate[x]，历史真实清单不伪勾。
- 私有查询/登录兼容、真实字段单位/权利范围、Cookie/Token生命周期、iCloud/物理Watch、后台通知与全部UI仍保留未验证边界。根本没有加入7个research provider，不以icon或stub关研究票。

## Pi冻结快照审查（尚未全部完成）

用户要求10个独立审查任务。最初zcode/glm-5.3-flash发生503后，改用cch/glm-5.3、4并发；当前仅报告01完成，不能宣称Pi10全过。Pi不运行Xcode/模拟器、不修改工作分支，root复现、分派和管理报告。

报告01发现Claude旧会话scope及WK重启问题。root在0477a43重建登录浏览器，sol_web正在修Claude范围；这些后续修复不自动包含在607项结果中。其余报告、复现修复、最终全量和unsigned结果由root补到[统一验证记录](validation-record.md)。本次文档整理不改Pi报告目录或validation-record。
