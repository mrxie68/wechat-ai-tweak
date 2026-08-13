#import <Foundation/Foundation.h>

// 微信内设置（NSUserDefaults 持久化，重启不丢）
@interface AISettings : NSObject

// 账号级数据隔离：设置当前微信账号后，所有设置按账号分开存储（切号互不串用）
+(void)setCurrentAccount:(NSString *)usrName;

+ (NSString *)autoSystemPrompt;        // 有自定义值返回自定义值，否则返回 AIConfig.h 默认
+ (void)setAutoSystemPrompt:(NSString *)prompt; // 传空则恢复默认
+ (NSString *)styleSamples;            // 聊天风格样本（可空，AI 会模仿这里的语气）
+ (void)setStyleSamples:(NSString *)samples;
+(NSString *)userProfile;            // 你的基础信息（设置页填，AI 聊天以此为准）
+(void)setUserProfile:(NSString *)profile;
+ (NSString *)styleProfileForChat:(NSString *)chatId;  // 自动学习的风格档案（按好友存）
+ (void)setStyleProfile:(NSString *)profile forChat:(NSString *)chatId;
+ (void)clearStyleProfileForChat:(NSString *)chatId;
+(void)clearAllStyleProfiles;           // 清掉所有好友的学习档案（设置页“清空全部记忆”用）
+ (NSInteger)styleProfileCount;        // 已学习的好友数量（状态里显示）
+(NSArray<NSDictionary *> *)allStyleProfiles;  // 全部学习档案 [{chatId, profile}]，按 chatId 排序
+(NSDictionary *)friendInfoForChat:(NSString *)chatId;  // 对方信息 {relation, favor, note}
+(void)setFriendInfo:(NSDictionary *)info forChat:(NSString *)chatId;
+(NSString *)writeBackupToFile;       // 备份全部 WeChatAI 配置到沙盒 Documents，成功返回路径
+(NSString *)latestBackupPath;        // 最近的备份文件路径（没有则 nil）
+(BOOL)restoreFromFile:(NSString *)path;  // 从备份文件整体恢复（覆盖当前配置）
+ (NSString *)apiKey;                  // 同理
+ (void)setApiKey:(NSString *)key;
+ (NSString *)model;
+ (void)setModel:(NSString *)model;
+ (NSString *)replyMode;              // @"auto" / @"trigger"，默认 kAIReplyMode
+ (void)setReplyMode:(NSString *)mode;
+ (BOOL)enabled;                       // 机器人总开关（默认开）
+ (void)setEnabled:(BOOL)enabled;
+(BOOL)isAccountActivated:(NSString *)usrName;                    // 该微信账号是否已激活（本地密钥，无远程验证）
+(void)setActivationKey:(NSString *)key forAccount:(NSString *)usrName;  // 设置密钥=激活本账号
+(void)deactivateAccount:(NSString *)usrName;                     // 停用该账号（清除密钥）
+(BOOL)groupQuestionOnly;              // 群聊只回提问（默认开）
+(void)setGroupQuestionOnly:(BOOL)value;
+(BOOL)stickerLightReply;              // 表情包轻回复（默认关，测试用）
+(void)setStickerLightReply:(BOOL)value;
+ (double)replyDelay;                  // 思考延迟（秒）
+ (void)setReplyDelay:(double)delay;
+(double)temperature;                  // 请求温度（默认 0.5）
+(void)setTemperature:(double)value;
+(double)frequencyPenalty;             // 频率惩罚（默认 0.4）
+(void)setFrequencyPenalty:(double)value;
+(double)presencePenalty;              // 存在惩罚（默认 0.4）
+(void)setPresencePenalty:(double)value;
+(BOOL)typingSimulation;                // 模拟打字（默认开，关闭后回复即时发出）
+(void)setTypingSimulation:(BOOL)value;
+ (BOOL)chatEnabled:(NSString *)chatId defaultEnabled:(BOOL)defaultEnabled; // 会话级开关
+ (void)setChatEnabled:(BOOL)enabled chatId:(NSString *)chatId;
+ (BOOL)chatEnabled:(NSString *)chatId;   // 默认关闭，只有聊天信息页单独开过才回

@end
