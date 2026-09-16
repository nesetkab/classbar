#import <Cocoa/Cocoa.h>

@class TaskComposer;

@interface ComposerPanel : NSPanel
@property (weak) TaskComposer *composer;
@end

@interface TaskComposer : NSObject
@property (strong) ComposerPanel *panel;
@property (strong) NSVisualEffectView *backdrop;
@property (strong) NSTextField *nameField;
@property (strong) NSDatePicker *dayPicker;
@property (strong) NSDatePicker *timePicker;
@property (strong) NSLayoutConstraint *widthRule;
@property (weak)   id target;
@property (assign) SEL addedAction;
@property (assign) BOOL adding;
- (void)showBelow:(NSView *)anchor width:(CGFloat)width;
- (void)add;
- (void)cancel;
- (NSDate *)chosenDue;
@end
