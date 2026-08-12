#ifndef AIConfig_h
#define AIConfig_h

// ============================================================
//  微信 AI 助手 - 配置文件
//  改完这些以后 push 到 GitHub，Actions 会自动编译
// ============================================================

// API Key（DeepSeek 示例，去 https://platform.deepseek.com 申请）
#define kAIAPIKey @"sk-xxxxxxxxxxxxxxxxxxxxxxxx"

// OpenAI 兼容接口地址（DeepSeek 默认）
#define kAIBaseURL @"https://api.deepseek.com"

// 模型名（deepseek-chat / gpt-4o-mini / glm-4-flash 等）
#define kAIModel @"deepseek-chat"

// 触发词：trigger 模式下，消息以这个词开头才会触发 AI
#define kAITrigger @"@AI"

// ============================================================
//  回复模式
// ============================================================
//
//  @"auto"    = 自动代替聊天：白名单会话里，别人发消息 AI 自动替你回复
//  @"trigger" = 手动触发：只有 @AI 开头的消息才回复
#define kAIReplyMode @"auto"

// 自动模式下的回复延迟（秒），稍微等一拍更像真人
#define kAIReplyDelaySeconds 1.0

// 自动模式下是否也回复群聊（建议 NO，群里人杂，容易出事）
#define kAIAutoReplyInGroups NO

// 自动模式下 AI 的系统提示词（AI 扮演的是你自己）
// 这是默认值；注入后可在微信里发“@AI 设置”修改，保存后立即生效、重启不丢
#define kAIAutoSystemPrompt @"你是微信用户本人，正在替 ta 和好友聊天。模仿 ta 平时自然、口语化的语气，不要解释自己是 AI，不要使用 @AI 之类的标记，回答简短自然，符合聊天语境。"

// 每个会话最多保留最近多少条消息作为上下文
#define kAIMaxContextMessages 30

// trigger 模式下 AI 的系统提示词
#define kAISystemPrompt @"你是微信里的一位 AI 助手，用简体中文简洁、友好地回答问题。"

// ============================================================
//  隐私保护（建议保持默认的最小读取模式）
// ============================================================
//
// 1. 只有白名单会话里的消息才会被读取；白名单外一律不读、不存、不传。
// 2. 上下文只记录“插件注入之后”该会话的双向消息（内存保存，重启微信即清空），
//    不会扫描或读取其他聊天记录。
//
// 会话白名单：AI 只在这些会话里生效。
//   单聊填对方 wxid（如 wxid_abc123），群聊填群 id（如 12345@chatroom）
//   多个用英文逗号分隔；留空表示所有会话都可以触发。
#define kAIAllowedChats @""

// 日志前缀（排查问题用，不用改）
#define kAITweakLogPrefix @"[WeChatAI] "

#endif
