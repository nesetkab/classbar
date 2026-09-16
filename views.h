#import <Cocoa/Cocoa.h>

extern const CGFloat kDueColumnGap;
extern const CGFloat kDoneCircleWidth;

@interface HoverTipView : NSView
@property (copy)   NSString *tip;
@property (strong) NSTimer *tipTimer;
@property (assign) BOOL tipShown;
@property (assign) BOOL hovered;
- (void)cancelTip;
- (void)scheduleTip;
- (void)syncHoverAt:(NSPoint)pt;
@end

@interface InfoTipView : HoverTipView
@end

@interface ComposeRowView : NSView <NSTextFieldDelegate>
@property (strong) NSTextField *nameField;
@property (strong) NSTextField *dayChip;
@property (strong) NSTextField *timeChip;
@property (strong, nonatomic) NSDate *dayValue;
@property (strong, nonatomic) NSDate *timeValue;
@property (weak)   id chipTarget;
@property (assign) SEL dayAction;
@property (copy)   NSString *cleanName;
@property (strong) NSDate *typedBase;
@property (assign) BOOL committed;
@property (assign) BOOL cancelled;
@property (strong) NSLayoutConstraint *nameLeading;
@property (weak)   id target;
@property (assign) SEL action;
- (NSDate *)chosenDue;
- (void)commit;
@end

@interface CalendarRowView : NSView
@property (strong) NSDatePicker *calendar;
@property (weak)   id target;
@property (assign) SEL action;
@end

@interface AssignmentView : HoverTipView
@property (copy) NSString *due;
@property (copy) NSString *name;
@property (copy) NSString *link;
@property (assign) BOOL late;
@property (assign) BOOL done;
@property (assign) BOOL overCircle;
@property (assign) CGFloat dueWidth;
@property (strong) NSDictionary *item;
@property (weak)   id target;
@property (assign) SEL toggleAction;
@end

@interface FooterView : NSView
@property (weak) id target;
@property (assign) SEL quitAction;
@property (assign) SEL refreshAction;
@property (assign) SEL settingsAction;
@property (assign) SEL plusAction;
@property (assign) BOOL overRefresh;
@property (assign) BOOL overGear;
@property (assign) BOOL overPlus;
@property (assign) BOOL overQuit;
@property (assign) BOOL hovered;
@property (copy)   NSString *status;
@end

void TipHide(void);
NSFont *DueFont(BOOL late);
NSFont *NameFont(void);

NSMenuItem *AssignmentItem(NSDictionary *item, NSString *due, NSString *name,
                           NSString *link, NSString *tip, BOOL late, BOOL done,
                           CGFloat dueWidth, CGFloat width,
                           id target, SEL toggleAction);
NSMenuItem *ComposeRowItem(NSString *name, NSDate *due,
                           id target, SEL action, id chipTarget,
                           SEL dayAction, CGFloat width);
NSMenuItem *CalendarRowItem(NSDate *due, id target, SEL action, CGFloat width);
NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
                     NSString *link, NSString *zoom, NSString *tip,
                     NSColor *bg, CGFloat width);
