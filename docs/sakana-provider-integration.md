# Sakana AI 额度与服务余额

`.sakana`接通用账号隔离WK登录与WebProviderSession，用户在console.sakana.ai/login自行登录，不导出Google或其它来源Cookie、不读本机浏览器/CLI凭证。仅采集console.sakana.ai/.sakana.ai的billing路径会话，排除统计、callback与CSRF Cookie。实际捕获的Auth.js session family可为未分块值或完整连续0…N chunks；缺块、混合整Cookie+分块、多个family均拒绝。本地UUID、origin、expiry、源hash绑定配置/Keychain/同步/旧缓存；过期/跳转/401/403需重登，无虚构续期。

Auth.js默认名与chunk机制有[官方框架源码a1a16a5a](https://github.com/nextauthjs/next-auth/blob/a1a16a5a7780488c7449feece410033f445d0b31/packages/core/src/lib/utils/cookie.ts)依据；品牌实际signed-in Cookie仍未实测，不把Pulse猜测的单一exact name说成已验证契约。通用视图会先查询额度成功才保存捕获会话；若生产自定义cookie family，应以真实契约适配，不能凭匿名CSRF cookie当登录。

GET /billing读取额度，GET /billing?tab=payAsYouGo读取服务余额。固定Origin、手工Cookie、禁缓存/自动Cookie/production重定向，Accept-Language en-US。只解析Usage limit卡片之后的5-hour/Weekly标签至下一个卡片/标签；脚本/样式/注释及其它Pricing卡片不参与。两个窗口分别读NN% used、服务渲染UTC时间，不取$20/mo价格或推算总额/日期。未知形状不生成0%，重复同label不选择第一份。余额辅助失败保留有效quota并标walletFailure，旧余额沿公共同身份/旧采集时间规则保留。

Credit balance区块只接受tabular-nums对应金额，不搜索全页美元/Total花费。Decimal数量保持精度，合法千位分组可读。明确USD/US$标记才构造USD货币余额；裸数字不造余额，单独$按非货币“$ credits”显示且标币种未提供、不触发货币提醒。调查日官方[Console Terms](https://console.sakana.ai/terms-of-service)称该Credits非货币等价资金，不能因美元样式或价格推断ISO币种/可赎回资金；该文档仅用于计量边界，不自行推算6个月账号余额到期。

卡片/详情/Watch/Widget/Demo使用mixed三种窗口，quota阈值及真正返回的reset沿既有规则，只有明确货币余额才开放低余额；未知单位或永久余额无百分比/重置。安全保存、多账号身份、重新登录/删除、iCloud-off本机使用与取得配置后的Watch直连沿共享路径，无Mac或设备外代理。

页面契约来自[固定Pulse397c8fc4文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/sakana.md)和[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/SakanaUsageService.swift)，其fixtures明确非signed capture。公开[登录页](https://console.sakana.ai/login)与Terms已只读获取，未建立登录。图标用Lobe Icons79b551cf的packages/static-svg/icons/sakana.svg，MIT/版权/path见notices；官方SakanaAI/AI-Scientist固定1de1dbc1树未提供SVG，未导入未许可的站点mark。

新增5个合成XCTest方法覆盖known卡片/UTC/plan、unknown vs明确USD、脚本/价格排除、实际chunks连续性、Cookie域与统计排除、固定请求/aux failure/expiry、scope/Widget/非货币提醒。工作者parse/PBX lint/diff与图标metadata检查通过，没执行Xcode/模拟器/大typecheck或真实凭证访问；root统一跑测试/build。当前实现+图标存在满足2026-10-02最新关票标准，真实Auth.js名/页面/金额单位、手机/Watch/iCloud与通知仍保留未验证说明。

2026-10-03 Pi08离线变体复核：Usage limit卡标题包一层span会被原裸文本比较拒绝。现只规范化至多2048字节/4层的inline span，禁止block、hidden/aria-hidden/style标题，仍只认最近的实际Usage limit card，Pricing或其他卡不扩大范围。计划名只取首卡中可识别的span名称，Usage limit/Credit balance等功能标题、价格不作为plan，不明确时保留nil。新增离线span/保留scope/误识别plan回归；真实生产parser+Domain的macOS离线驱动修前失败、修后读取92且功能标题plan=nil，负例通过。没有线上DOM变更/实际账户故障证据，完整XCTest仍由root跑；不改钱包单位或auth规则。
