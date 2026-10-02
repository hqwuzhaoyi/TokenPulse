# Windsurf 网页会话与 Connect 额度

Windsurf 复用Devin完成的同源网页存储登录路径，但provider、origin和scope独立。添加／重新登录打开临时 `https://windsurf.com/profile`；只读取windsurf.com localStorage四个固定key：devin_session_token、devin_auth1_token、devin_account_id、devin_primary_org_id。只unwrap一次JSON-string编码；缺任一项、空项、控制字符或错误origin不发送半套查询。四项作为单次storage读取的同源会话，由远程额度probe验证后安全保存。普通浏览器、Mac编辑器缓存和app.devin.ai不是此provider的读取来源。

WebProviderSession将session token、auth1、远端账号、组织、origin和本机账号UUID一并绑定fingerprint，查询时由实际值重算；更换组织／账号／凭证不能把旧scope当新数据。所有查询都由iPhone／Watch各自直连，不需另一设备、Mac或新代查服务；配好凭证后Watch不依赖WKWebView。添加、安全保存、重新登录、本机与iCloud关闭模式、配置/Keychain同步、删除沿用现有应用路径。显式expiry、401/403/redirect需要重新登录；其它失败保留原snapshot／原时间。

请求是 `POST https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus`，Content-Type/Accept application/proto，Connect-Protocol-Version 1、固定Origin/Referer、x-auth-token、x-devin-session-token、x-devin-auth1-token、x-devin-account-id与x-devin-primary-org-id。body只含field1 session token和field2 include_top_up_status=true。符合Connect官方unary协议：bare protobuf，没有gRPC-style五字节包框。

响应field1 plan_status，其field1 plan_info的field2为plan name；field14/15是每日／每周**剩余**百分比，used=100-remaining；field17/18为Unix秒reset。只读明确字段，没有剩余字段时不把protobuf默认0当已用尽；显式写入0才是耗尽。没有reset就不猜。parser校验完整外层／plan_status／plan_info、合法field id、十字节varint溢出、长度与固定wire宽度、日期范围和比例范围；未知普通wire字段按类型跳过，截断或非法wire整体拒绝，保证Watch整数转换不越界。plan_end、topup status、grace不是usage，不生成虚构余额或百分比。

官方主源：[Windsurf Plans and Usage](https://docs.windsurf.com/windsurf/accounts/usage)，2026-10-02读取时已展示Devin Desktop品牌并指向app.devin.ai，确认当前使用量入口与迁移背景；并非此内部protobuf字段的公开schema。[Connect官方协议](https://connectrpc.com/docs/protocol/)确认application/proto unary framing和HTTP错误模型。后台路由／storage key／protobuf field及合成base64 fixture来自[Pulse固定397c8fc4 Windsurf说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/windsurf.md)与同版本WindsurfUsageService、windsurf-plan-status fixture，按契约独立适配，没有把second-hand包字段声称为真实本机捕获。

ProviderWindsurf图标已存在：Lobe Icons固定commit `7970dce20b059ed397389e874929bf0f6a10d2db`，`packages/static-svg/icons/windsurf.svg`，Copyright (c) 2023 LobeHub，MIT。notice记录来源/版权/许可证；SVG只改currentColor为black、尺寸24x24，开启vector-preserving template imageset。App/Watch/widget/demo均有两个独立窗口，provider鉴权和查询注册到既有管线。

8个Windsurf测试覆盖四项完整性／quoted值／origin、fixture计划与剩余比例、字段缺失与显式零、varint/长度/嵌套截断/非法wire、Connect body和headers、scope篡改/expiry/HTTP错误、本机失败保留与删除、demo/widget/icon。源码parser/PBX/diff/asset存在与XML/JSON检查通过；另直接运行提取自实现的Foundation小模块，固定protobuf fixture的daily68/weekly84与坏wire边界通过。没有重复大模块typecheck、没有Xcode／模拟器或真实账户访问，root统一编译／执行XCTest。

按用户新标准，全链路接入和图标存在完成，62 done。真实Windsurf登录、目前旧domain与迁移后服务的账号兼容、完全耗尽时字段可选性和真机双端独立刷新仍没有实测；这些真实性项目保留事实记录，不再作为关票条件。
