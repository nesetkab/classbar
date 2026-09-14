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
@property (assign) BOOL pinned;
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
@property (assign) BOOL overRefresh;
@property (assign) BOOL overGear;
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
NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
                     NSString *link, NSString *zoom, NSString *tip,
                     NSColor *bg, CGFloat width);
