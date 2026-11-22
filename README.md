# 欧易AI跟单（OKXAICopilot）

iOS 原生（SwiftUI）欧易(OKX)交易客户端，仿欧易官方 App 的简约实用 UI，全中文界面。
行情/持仓/委托/账户均为 **欧易官方 V5 API 真实数据**，下单/撤单/止盈止损为 **真实可操作交易**。

## 功能总览

| 模块 | 功能 |
|---|---|
| 行情 | 现货全量行情列表（WebSocket 实时推送）、搜索、K线图（1m~1D，Canvas 自绘）、盘口深度 |
| 止盈止损 | K线图下方直接设置（策略委托 OCO/条件单，触发后市价成交），持仓页可对单个仓位设置；策略委托列表可查看/撤销 |
| 交易 | 现货 + 永续合约，限价/市价、买卖、杠杆 1–20x、可用余额一键 25/50/75/100%、下单前二次确认（明示模拟盘/实盘） |
| 持仓 | 合约持仓（多空/杠杆/开仓均价/未实现盈亏）、跟单来源标签、市价平仓（reduceOnly） |
| 委托 | 当前委托（侧滑撤单）、历史订单、账户信息（总权益 USD、账户模式、UID、币种明细） |
| 跟单 | 欧易公开带单大厅（真实排行数据）、交易员收益走势图、当前带单持仓、**一键跟卖**（按交易员反方向真实下单） |
| AI助手 | **自行接入任意 OpenAI 兼容模型 Key**（GPT / DeepSeek / Kimi 等），AI 可查行情/K线/持仓/余额，并可执行下单与撤单（对话中展示执行日志） |
| 桌面小组件 | WidgetKit 欧易行情小组件：小（BTC）/ 中（4币）/ 大（8币）三种尺寸，真实行情，15 分钟自动刷新 |

## 环境要求

- macOS + Xcode 15+（iOS 16.0+ 真机/模拟器）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用于生成工程）：`brew install xcodegen`

## 构建步骤

```bash
cd OKXAICopilot
xcodegen          # 生成 OKXAICopilot.xcodeproj
open OKXAICopilot.xcodeproj
```

1. 在 Xcode 中选择自己的开发者团队（Signing & Capabilities，主 App 与 Widget 两个 target 都要设置）。
2. 运行到真机或模拟器。
3. 进入「我的 → 设置」：
   - 填入欧易 API Key / Secret / Passphrase（欧易官网 → API → 创建，建议只开「交易」权限）；
   - 选择 **模拟盘 / 实盘**（强烈建议先用模拟盘：欧易网页端「模拟交易」生成模拟盘 API）；
   - 填入 AI 模型接口地址、API Key、模型名称（任意 OpenAI 兼容服务）。

## 目录结构

```
OKXAICopilot/
├── project.yml                    # XcodeGen 工程定义（App + Widget 两个 target）
└── Sources/
    ├── App/                       # App 入口、TabView、主题
    ├── Core/                      # OKX V5 客户端（HMAC 签名/REST/WebSocket）、配置与 Keychain
    ├── Models/                    # 行情/订单/持仓/账户/带单数据模型
    ├── Services/                  # 交易服务、AI 服务（OpenAI 兼容 + 工具调用）
    ├── Features/
    │   ├── Market/                # 行情、K线、盘口、止盈止损卡片
    │   ├── Trade/                 # 交易下单
    │   ├── Orders/                # 持仓/委托/策略委托/历史/账户信息
    │   ├── CopyTrade/             # 跟单大厅、交易员详情、一键跟卖
    │   ├── AI/                    # AI 对话
    │   └── Settings/              # API/模型配置
    └── Widget/                    # 欧易行情桌面小组件
```

## 安全与风险说明

- API 密钥仅保存在 iOS Keychain，不上传任何服务器。
- 请勿开启 API Key 的提币权限。
- 实盘下单、平仓、止盈止损、AI 下单均为真实委托，请务必先在模拟盘验证。
- 加密货币交易风险极高，本应用仅为工具，不构成投资建议。

## 说明

- 欧易「公开跟单」接口仅提供带单员公开数据（排行榜、持仓、收益走势）；真实的一键复制跟单需欧易授权的跟单权限，本项目采用「查看带单持仓 → 一键反向下单」的手动跟单方式实现可操作跟单。
- 小组件刷新频率受系统限制（最短约 15 分钟）。
- 本工程在 Linux 环境编写，未经过 Xcode 编译验证，首次构建如遇个别 API 兼容问题（SwiftUI 版本差异），按报微调即可。
