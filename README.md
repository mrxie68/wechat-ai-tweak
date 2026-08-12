# 微信 AI 助手插件（iOS dylib）

一个能理解上下文的微信 AI 聊天插件：支持两种模式——

- **自动模式（默认）**：白名单会话里，别人发消息，AI 自动以“你”的身份回复，真正代替你聊天。
- **触发模式**：只有以 `@AI` 开头的消息才会回复，像带了个 AI 助手。

纯 Objective-C 运行时实现，**不依赖 Theos / CydiaSubstrate**，所以同一个 dylib 既可以：

- **TrollStore + TrollFools 直接注入微信**（推荐，不需要越狱、不需要重新签名 ipa）
- 越狱环境放进 `DynamicLibraries` 由 MobileSubstrate 加载（也提供 deb 包）

## 你要准备

1. GitHub 账号。公开仓库免费不限时长；私有仓库每月 2000 分钟额度（macOS 按 10 倍扣，约 200 分钟，够用）。
2. iPhone：TrollStore + TrollFools（或越狱机）。
3. 一个 API Key。默认配的是 DeepSeek，去 [platform.deepseek.com](https://platform.deepseek.com) 注册充值即可。

## 快速开始

1. 编辑 [AIConfig.h](AIConfig.h)，填上你的 API Key、模型名，并选择回复模式（`kAIReplyMode`：`auto` / `trigger`）。提示词有内置默认值，注入后也能在微信里改，不用为它重新编译。
2. 推送到 GitHub（仓库保持公开就有免费 macOS 编译时长）。
3. 打开仓库的 Actions 标签，等 `Build WeChat AI` 跑完，下载 `wechat-ai-dylib` 这个 artifact，里面有 `wechat-ai.dylib`。
4. iPhone 上把 dylib 分享给 TrollFools → 选择微信 → 注入 → 重启微信。
5. 重启微信后 2 秒左右会弹一次“微信 AI 助手已加载”（仅首次），没弹说明注入没成功，检查 TrollFools → 微信 → 插件列表里有没有 `wechat-ai.dylib`。
6. 自动模式：在白名单会话里让对方发条消息试试；触发模式：发 `@AI 你好`。

越狱用户：下载 `wechat-ai-deb` 直接安装（依赖 CydiaSubstrate），或者把 dylib 手动放进 `/Library/MobileSubstrate/DynamicLibraries/` 并配好同名 plist。

## 自动模式怎么工作

- 上下文 = 白名单会话里“插件注入之后”的双向消息：对方的消息算 `user`，你自己发的（包括 AI 替你的回复）算 `assistant`。AI 扮演的就是你。
- 有 `kAIReplyDelaySeconds` 秒的延迟，更像真人；回复期间对方继续发消息会一起并入上下文，只回一次。
- 群聊默认不自动回复（`kAIAutoReplyInGroups = NO`），群里只认 `@AI` 触发，避免误回复。
- 自动模式下，你自己发 `@AI 清空`（或 `@AI 问题`）仍按手动命令/提问处理，不会混进自动聊天。
- 注意：插件注入之前的聊天记录读不到（那需要直接读微信数据库，属于另一档复杂度）；上下文是从注入那一刻开始累积的，重启微信后清空。

## 在微信里设置提示词

- 直接给自己发（或任意会话）`@AI 设置`，会弹出提示词编辑页，修改“自动回复时 AI 扮演你的要求”。大部分微信版本命令会被拦截不真的发出；个别版本拦截不生效时，消息会留在会话里，但设置页照常弹出——所以最稳妥是发给文件助手。
- 点“保存”立即生效，存在微信本地，重启不丢；点“恢复默认”回到 [AIConfig.h](AIConfig.h) 里 `kAIAutoSystemPrompt` 的值。
- 设置页是插件自己弹出的独立页面，不 hook 微信设置列表，换微信版本一般也不会失效。
- `@AI 清空` 同样拦截处理，不会发出去。

## 隐私与安全（默认最小读取）

- 只有**白名单会话**里的消息才会被读取，白名单外一律**不读、不存、不传**。
- 自动模式下，AI 会读取白名单会话里注入之后的对话用于模仿聊天；触发模式则只处理 `@AI` 消息。
- 上下文上限 30 条，保存在内存中，**重启微信即清空**；插件不落盘、不扫描其他会话、不上传任何额外信息。
- 会话白名单：在 [AIConfig.h](AIConfig.h) 的 `kAIAllowedChats` 里填允许的 wxid 或群 id（逗号分隔），留空则所有会话可触发。建议只填你自己常用的几个会话。
- 发 `@AI 清空` 可以随时手动清空当前会话上下文。

> 说明：技术上 hook 层会“经过”所有消息，但代码对白名单外的消息直接丢弃，不做任何存储或请求。自动代替聊天有风险——AI 会以你的名义说话，请务必只在可信的小号/测试号上使用，并清楚告知对方。

## 换其他 API

所有 OpenAI 兼容接口都是同一个 `/chat/completions` 格式，只改 AIConfig.h 里三个值：

| 服务 | kAIBaseURL | kAIModel |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| OpenAI | `https://api.openai.com` | `gpt-4o-mini` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash` |
| Moonshot Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |

## 常见问题

- **发了 `@AI` 没反应**：微信版本可能改了 hook 点。当前基于 `CMessageMgr` 的 `AsyncOnAddMsg:MsgWrap:` 收消息、`SendTextMessage:toUsrName:` 发消息，兼容大多数 7.x / 8.x 版本。确认方法：用 Console.app 或 Xcode 连接设备看日志，搜 `[WeChatAI]`。
- **上下文**：存在内存里，重启微信会清空；发 `@AI 清空` 可以手动清空。
- **群聊**：直接在群里发 `@AI xxx` 就会触发。
- **封号风险**：这是非官方注入插件，微信有检测手段，务必先用小号测试，风险自负。
- **API Key 泄露**：公开仓库所有人都能看到源码。建议用单独充值的 key，或者仓库设私有（也能用，只是每月额度少一些）。

## 目录结构

```
wechat-ai-tweak/
├── AIConfig.h            # 改这里：API Key / 模型 / 触发词
├── AIContext.h/.m        # 会话上下文管理
├── AIAPIClient.h/.m      # OpenAI 兼容接口调用
├── WeChatAITweak.m       # 微信 hook + 触发逻辑
├── build.sh              # 编译 dylib（Actions 里跑）
├── package_deb.sh        # 打包 deb（Actions 里跑）
├── packaging/            # deb 目录结构（control + plist）
└── .github/workflows/    # 自动编译工作流
```

## 免责声明

仅供个人学习研究，请勿用于商业或非法用途；使用造成的任何后果（包括但不限于微信功能限制、封号）由使用者自行承担。
