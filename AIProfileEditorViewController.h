#import <UIKit/UIKit.h>

// 风格档案编辑器：展示完整档案内容，用户可手动修改完善
@interface AIProfileEditorViewController : UIViewController
- (instancetype)initWithChatId:(NSString *)chatId profile:(NSString *)profile;
@end
