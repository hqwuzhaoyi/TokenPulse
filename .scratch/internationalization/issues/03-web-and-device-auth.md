# 03: 网页登录与设备授权流程

**What to build:** 用户能以所选语言完成应用引导的网页登录或设备授权、选择服务范围，并在过期或失败后知道如何恢复。

**Blocked by:** 01 — 语言基础与首页首条完整路径

**Status:** complete

- [x] 覆盖应用管理的网页登录、OAuth、设备码、会话导入、组织或工作区选择、轮询、取消、过期和重新授权说明。
- [x] 第三方网页和提供商返回的原始内容不自动翻译；应用自己的指导与错误解释支持双语，技术术语允许英文。
- [x] 验证码、回调地址、授权 URL、服务账号及组织身份保持原样；展示语言不影响请求、回调解析和授权链。
- [x] 复用现有登录/设备授权测试替身，验证成功、等待、取消、过期和失败恢复输出，至少覆盖网页登录与设备码两条代表性路径。
- [x] 盘点所有授权分支的应用自有文案并覆盖，不能仅翻译一个 Provider 即视为完成。
- [x] 两种语言下验证指引、复制、打开授权页及恢复操作，检查长文案和辅助功能；沿用现有设备本地授权与凭证同步边界。

共同约束：首期仅简体中文与英文，复用现有展示/通知行为测试边界。常用英文术语不算漏翻译；不改变 Provider API、数据身份或授权架构，不自动翻译用户输入与第三方内容。每票完成自身范围的双语行为及可视验证，不能把质量检查全部留给最后一票。

## 中央验收完成

- `02-05-behavior-tests-signed.log`：781 XCTest+18 Swift Testing、0 failures；03范围全部既有与新增Device/Google/StepFun/Session/Nous用例真实执行，成功/取消/拒绝/过期/恢复以及完整请求字段/URL/headers/身份不变验证通过。新增JSON byte脆弱断言已改为解码后全字段严格比较，未改产品请求。
- `03-ui-auth-all.log`：Google和JetBrains中英4个UI用例分别通过；该整轮未通过，因为设备码native定位错误（不能算全绿），日志保留。
- 真实a11y tree证实系统把“授权码, TEST-CODE”合并为StaticText且授权Link映射Button，修正harness定位后 `03-ui-device-verified.log` 两语2 UI test、0失败，实际恢复等待、点击授权入口（fixture OpenURL handled，不访问外站）、长按及原生Copy菜单、Cancel均执行。验证码保持原文。
- 中英Google、JetBrains、deviceRecovery截图/a11y树全部导出并实际查看；长指导通过原生Form换行/滚动，未遮挡取消/授权动作。资源100条来自03片段已原生打包四目标。
- 无秘密DEBUG fixture只注入已有DeviceLoginModel transport，不改默认controller/授权链；Release无fixture route，未把第三方网页/原始workspace/model/plan名称译为新身份。
