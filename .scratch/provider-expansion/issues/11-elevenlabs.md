# 11: ElevenLabs 字符额度接入

**Status:** in-progress

**Type:** integration

**What to build:** 用户输入具有 user_read 权限的 Key，在双端查看账期字符用量与重置时间。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 明确说明所需只读权限，区分无效 Key 与缺少权限，使用服务要求的认证头。
- [ ] 显示字符已用、字符上限和实际重置时间；零上限不显示伪造百分比，不将 voice slots 当成消耗型额度。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/elevenlabs.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。

## 实施记录（2026-10-02，root）

已实现 API Key 配置、字符额度解析、独立双端查询路由、小组件与演示数据、查询权限错误提示及固定来源图标。自定义 xi-api-key 请求拒绝重定向。已添加五项测试，覆盖账户隔离、认证头、字段与权限边界、通知和 Widget；Swift 语法检查与 PBX plist 校验通过。完整构建与 XCTest 等待匹配的 iOS 运行时安装；真实账号和物理 Watch 尚未验证，验收项保留未勾选。
