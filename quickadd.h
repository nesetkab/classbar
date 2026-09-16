#import <Cocoa/Cocoa.h>

@interface TaskComposer : NSObject <NSPopoverDelegate>
@property (strong) NSPopover *popover;
@property (strong) NSTextField *nameField;
@property (strong) NSDatePicker *dayPicker;
@property (strong) NSDatePicker *timePicker;
@property (weak)   id target;
@property (assign) SEL addedAction;
@property (assign) BOOL adding;
@property (strong) NSVisualEffectView *backdrop;
@property (strong) NSLayoutConstraint *widthRule;
- (void)showRelativeTo:(NSView *)anchor width:(CGFloat)width;
- (void)add;
- (void)cancel;
- (NSDate *)chosenDue;
@end
