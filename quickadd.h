#import <Cocoa/Cocoa.h>

@interface TaskComposer : NSObject <NSPopoverDelegate>
@property (strong) NSPopover *popover;
@property (strong) NSTextField *nameField;
@property (strong) NSDatePicker *dayPicker;
@property (strong) NSDatePicker *timePicker;
@property (weak)   id target;
@property (assign) SEL addedAction;
@property (assign) BOOL adding;
- (void)showRelativeTo:(NSView *)anchor;
- (void)add;
- (void)cancel;
- (NSDate *)chosenDue;
@end
