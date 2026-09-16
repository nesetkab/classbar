#import <Cocoa/Cocoa.h>

@interface QuickAddWindow : NSObject
@property (strong) NSWindow *window;
@property (strong) NSTextField *nameField;
@property (strong) NSDatePicker *duePicker;
@property (weak)   id target;
@property (assign) SEL addedAction;
- (void)show;
- (void)add;
@end
