# ClawRouter 托管预算

直接 GET https://clawrouter.openclaw.ai/v1/usage，使用 Key 查询托管 OpenClaw ClawRouter；不混同 BlockRunAI 同名 x402 钱包项目。预算值来自整数微美元，存入 Decimal 精确数量，仅输出预算使用率而非 API 钱包。

一手固定 [openclaw/clawrouter e947a93](https://github.com/openclaw/clawrouter/blob/e947a93ac20f5988e8efb247ea19ccac599fb9f7/worker/test/usage-budget.test.mjs) 验证 configured、limitMicros、spentMicros、windowKey 形状；来源仍非本人的账号验收。windowKey 只作服务给出的周期身份，绝不推算月初时刻或时区。无配置、零上限不生成耗尽比例。保留微美元精度与近阈值边界。

图标使用官方 OpenClaw 原生模板SVG，固定版本、路径、版权和 MIT 声明已记入 notices。测试覆盖真实整数形状、未知/错误布尔/非整数、精确数量、周期不猜时间和Widget预算语义。真实Key、物理Watch和iCloud尚待验收。
