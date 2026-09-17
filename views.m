#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "views.h"
#import "icons.h"
#import "schedule.h"
#import "store.h"

const CGFloat kDueColumnGap = 10.0;
const CGFloat kDoneCircleWidth = 26.0;

static const CGFloat kRowInset = 5.0;
static const CGFloat kTextInset = 9.0;
static const CGFloat kRowRadius = 6.0;

NSColor *TaskColor(void) {
    return [NSColor colorWithSRGBRed:0.478 green:0.780 blue:0.769 alpha:1.0];
}

NSString *SquashKey(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    NSMutableString *out = [NSMutableString string];
    NSString *low = s.lowercaseString;
    for (NSUInteger i = 0; i < low.length; i++) {
        unichar c = [low characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
            [out appendFormat:@"%C", c];
    }
    return out;
}

NSArray *CoursePalette(void) {
    static NSArray *palette;
    if (!palette)
        palette = @[[NSColor colorWithSRGBRed:0.722 green:0.655 blue:0.945 alpha:1.0],
                    [NSColor colorWithSRGBRed:0.635 green:0.894 blue:0.796 alpha:1.0],
                    [NSColor colorWithSRGBRed:0.980 green:0.776 blue:0.643 alpha:1.0],
                    [NSColor colorWithSRGBRed:0.965 green:0.694 blue:0.741 alpha:1.0],
                    [NSColor colorWithSRGBRed:0.937 green:0.878 blue:0.671 alpha:1.0],
                    [NSColor colorWithSRGBRed:0.788 green:0.867 blue:0.678 alpha:1.0]];
    return palette;
}

NSColor *NoticeColor(void) {
    return [NSColor colorWithSRGBRed:0.651 green:0.839 blue:0.933 alpha:1.0];
}

NSColor *CourseColor(NSString *key) {
    static NSArray *palette;
    if (!palette) palette = CoursePalette();
    NSString *squashed = SquashKey(key);
    if (!squashed.length) return nil;
    unsigned long hash = 5381;
    for (NSUInteger i = 0; i < squashed.length; i++)
        hash = hash * 33 + [squashed characterAtIndex:i];
    return palette[hash % palette.count];
}

NSColor *PaleColor(NSColor *c) {
    return [c blendedColorWithFraction:0.45 ofColor:[NSColor whiteColor]] ?: c;
}

static NSImage *Symbol(NSString *name, CGFloat pt, NSColor *color) {
    NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!img) return nil;
    NSImageSymbolConfiguration *size =
        [NSImageSymbolConfiguration configurationWithPointSize:pt
                                                        weight:NSFontWeightSemibold
                                                         scale:NSImageSymbolScaleMedium];
    NSImageSymbolConfiguration *tint =
        [NSImageSymbolConfiguration configurationWithHierarchicalColor:color];
    return [img imageWithSymbolConfiguration:
        [size configurationByApplyingConfiguration:tint]];
}

static void DrawSymbol(NSString *name, CGFloat pt, NSColor *color, NSRect box) {
    NSImage *img = Symbol(name, pt, color);
    if (!img) return;
    NSSize sz = img.size;
    NSRect r = NSMakeRect(NSMidX(box) - sz.width / 2, NSMidY(box) - sz.height / 2,
                          sz.width, sz.height);
    [img drawInRect:r fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver fraction:1.0];
}

static BOOL CardHasDetail(NSString *when, NSString *room, NSString *zoom) {
    return when.length > 0 || room.length > 0 || zoom.length > 0;
}

static CGFloat CardHeight(NSString *when, NSString *room, NSString *zoom,
                          CGFloat progress, BOOL first) {
    CGFloat base = CardHasDetail(when, room, zoom)
                 ? (progress > 0 ? 61.0 : 51.0) : 33.0;
    return base + (first ? kRowInset / 2 : 0);
}

static NSPanel *gTipPanel;
static NSTextField *gTipLabel;

void TipHide(void) {
    [gTipPanel orderOut:nil];
}

static void TipShowNear(NSString *text, NSRect anchor, BOOL preferRight) {
    if (!text.length) { TipHide(); return; }

    if (!gTipPanel) {
        gTipPanel = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 40, 20)
                      styleMask:NSWindowStyleMaskBorderless |
                                NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        gTipPanel.opaque = NO;
        gTipPanel.backgroundColor = [NSColor clearColor];
        gTipPanel.hasShadow = YES;
        gTipPanel.level = NSPopUpMenuWindowLevel + 1;
        gTipPanel.ignoresMouseEvents = YES;
        gTipPanel.floatingPanel = YES;
        gTipPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                       NSWindowCollectionBehaviorFullScreenAuxiliary |
                                       NSWindowCollectionBehaviorIgnoresCycle;

        NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
        bg.material = NSVisualEffectMaterialToolTip;
        bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        bg.state = NSVisualEffectStateActive;
        bg.wantsLayer = YES;
        bg.layer.cornerRadius = 6;
        bg.layer.masksToBounds = YES;

        gTipLabel = [NSTextField labelWithString:@""];
        gTipLabel.font = [NSFont systemFontOfSize:11.5];
        gTipLabel.textColor = [NSColor labelColor];
        gTipLabel.lineBreakMode = NSLineBreakByWordWrapping;
        gTipLabel.maximumNumberOfLines = 0;
        [bg addSubview:gTipLabel];
        gTipPanel.contentView = bg;
    }

    gTipLabel.stringValue = text;
    gTipLabel.preferredMaxLayoutWidth = 280;
    NSSize ts = [gTipLabel sizeThatFits:NSMakeSize(280, 4000)];
    ts.width = ceil(ts.width);
    ts.height = ceil(ts.height);
    gTipLabel.frame = NSMakeRect(9, 6, ts.width, ts.height);

    CGFloat w = ts.width + 18, h = ts.height + 12;
    NSRect frame = NSMakeRect(preferRight ? NSMaxX(anchor) + 8
                                          : NSMinX(anchor) - 8 - w,
                              NSMidY(anchor) - h * 0.5, w, h);

    NSScreen *scr = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens])
        if (NSIntersectsRect(s.frame, anchor)) { scr = s; break; }
    NSRect vis = scr.visibleFrame;
    if (NSMinX(frame) < NSMinX(vis) + 6) frame.origin.x = NSMaxX(anchor) + 8;
    if (NSMaxX(frame) > NSMaxX(vis) - 6)
        frame.origin.x = NSMinX(anchor) - 8 - NSWidth(frame);
    if (NSMinX(frame) < NSMinX(vis) + 6) frame.origin.x = NSMinX(vis) + 6;
    if (NSMinY(frame) < NSMinY(vis) + 6) frame.origin.y = NSMinY(vis) + 6;
    if (NSMaxY(frame) > NSMaxY(vis) - 6) frame.origin.y = NSMaxY(vis) - 6 - NSHeight(frame);

    [gTipPanel setFrame:frame display:NO];
    [gTipPanel orderFrontRegardless];
}

@implementation InfoTipView

- (NSSize)intrinsicContentSize {
    return NSMakeSize(16, 16);
}

- (void)syncHoverAt:(NSPoint)pt __unused {
    if (!self.hovered) { self.hovered = YES; self.needsDisplay = YES; }
    if (self.tipShown) return;
    self.tipShown = YES;
    TipShowNear(self.tip, [self.window convertRectToScreen:
        [self convertRect:self.bounds toView:nil]], YES);
}

- (void)drawRect:(NSRect)dirty __unused {
    DrawSymbol(@"info.circle", 12,
               self.hovered ? [NSColor labelColor] : [NSColor tertiaryLabelColor],
               self.bounds);
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityButtonRole;
}

- (NSString *)accessibilityLabel {
    return self.tip;
}

@end

@implementation MenuFieldEditor

- (NSRect)caretRect {
    NSLayoutManager *lm = self.layoutManager;
    NSTextContainer *tc = self.textContainer;
    [lm ensureLayoutForTextContainer:tc];

    NSUInteger loc = MIN(self.selectedRange.location, self.string.length);
    NSUInteger glyph = [lm glyphIndexForCharacterAtIndex:loc];
    NSRect before = glyph ? [lm boundingRectForGlyphRange:NSMakeRange(0, glyph)
                                          inTextContainer:tc]
                          : NSZeroRect;
    NSFont *font = self.font ?: [NSFont systemFontOfSize:12];
    CGFloat height = NSHeight(before) > 0 ? NSHeight(before)
                                          : ceil(font.ascender - font.descender);
    NSPoint origin = self.textContainerOrigin;
    return NSMakeRect(origin.x + NSMaxX(before), origin.y + NSMinY(before), 1, height);
}

- (void)relightCaret {
    self.blinkOn = YES;
    self.needsDisplay = YES;
}

- (void)startBlink {
    if (self.blinkTimer) return;
    __weak MenuFieldEditor *me = self;
    self.blinkTimer = [NSTimer timerWithTimeInterval:0.53 repeats:YES
                                               block:^(NSTimer *t __unused) {
        me.blinkOn = !me.blinkOn;
        [me setNeedsDisplayInRect:NSInsetRect([me caretRect], -2, -2)];
    }];
    for (NSString *mode in @[NSRunLoopCommonModes, NSEventTrackingRunLoopMode])
        [[NSRunLoop currentRunLoop] addTimer:self.blinkTimer forMode:mode];
    [self relightCaret];
}

- (void)stopBlink {
    [self.blinkTimer invalidate];
    self.blinkTimer = nil;
    self.blinkOn = NO;
}

- (BOOL)becomeFirstResponder {
    BOOL ok = [super becomeFirstResponder];
    if (ok) [self startBlink];
    return ok;
}

- (BOOL)resignFirstResponder {
    if (self.holdsFocus && self.window) return NO;
    [self stopBlink];
    return [super resignFirstResponder];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self stopBlink];
}

- (void)didChangeText {
    [super didChangeText];
    [self relightCaret];
}

- (void)setSelectedRanges:(NSArray<NSValue *> *)ranges
                 affinity:(NSSelectionAffinity)affinity
           stillSelecting:(BOOL)selecting {
    [super setSelectedRanges:ranges affinity:affinity stillSelecting:selecting];
    [self relightCaret];
}

- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    if (!self.string.length && self.placeholder.length) {
        NSPoint at = self.textContainerOrigin;
        [self.placeholder drawAtPoint:at withAttributes:@{
            NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        }];
    }
    if (!self.blinkOn || !self.isEditable) return;
    [(self.insertionPointColor ?: [NSColor labelColor]) setFill];
    NSRectFill([self caretRect]);
}

- (void)dealloc {
    [self stopBlink];
}

@end

@implementation ComposeRowView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;

    self.nameField = [[MenuFieldEditor alloc] initWithFrame:NSMakeRect(0, 0, 200, 16)];
    self.nameField.placeholder = @"new task";
    self.nameField.editable = YES;
    self.nameField.selectable = YES;
    self.nameField.richText = NO;
    self.nameField.drawsBackground = NO;
    self.nameField.insertionPointColor = [NSColor labelColor];
    self.nameField.font = [NSFont systemFontOfSize:12];
    self.nameField.textColor = [NSColor labelColor];
    self.nameField.focusRingType = NSFocusRingTypeNone;
    self.nameField.verticallyResizable = NO;
    self.nameField.horizontallyResizable = NO;
    self.nameField.textContainerInset = NSZeroSize;
    self.nameField.textContainer.lineFragmentPadding = 0;
    self.nameField.textContainer.widthTracksTextView = YES;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameField.delegate = self;

    self.dayChip = [NSTextField labelWithString:@""];
    self.dayChip.font = [NSFont systemFontOfSize:11];
    self.dayChip.alignment = NSTextAlignmentCenter;
    self.dayChip.textColor = [NSColor labelColor];
    self.dayChip.translatesAutoresizingMaskIntoConstraints = NO;

    self.timeChip = [NSTextField labelWithString:@""];
    self.timeChip.font = [NSFont systemFontOfSize:11];
    self.timeChip.alignment = NSTextAlignmentCenter;
    self.timeChip.textColor = [NSColor secondaryLabelColor];
    self.timeChip.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:self.nameField];
    [self addSubview:self.dayChip];
    [self addSubview:self.timeChip];
    self.nameLeading = [self.nameField.leadingAnchor
        constraintEqualToAnchor:self.leadingAnchor constant:kRowInset + kTextInset];
    [NSLayoutConstraint activateConstraints:@[
        self.nameLeading,
        [self.nameField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.nameField.heightAnchor constraintEqualToConstant:16],
        [self.dayChip.leadingAnchor
            constraintEqualToAnchor:self.nameField.trailingAnchor constant:10],
        [self.dayChip.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.timeChip.leadingAnchor
            constraintEqualToAnchor:self.dayChip.trailingAnchor constant:8],
        [self.timeChip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                       constant:-(kRowInset + kTextInset)],
        [self.timeChip.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

- (void)setDayValue:(NSDate *)day {
    _dayValue = day;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"EEE M/d";
    self.dayChip.stringValue = day ? [f stringFromDate:day].lowercaseString : @"";
}

- (void)setTimeValue:(NSDate *)time {
    _timeValue = time;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"h:mm a";
    self.timeChip.stringValue = time ? [f stringFromDate:time].lowercaseString : @"";
}

- (NSRect)dayChipRect {
    return NSInsetRect(self.dayChip.frame, -8, -3);
}

- (void)mouseDown:(NSEvent *)e __unused {
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    if (!NSPointInRect(pt, [self dayChipRect])) return;
    if (self.dayAction && self.chipTarget)
        ((void (*)(id, SEL, id))objc_msgSend)(self.chipTarget, self.dayAction, self);
}

- (NSDate *)chosenDue {
    return CombineDayAndTime(self.dayValue ?: [NSDate date],
                             self.timeValue ?: [NSDate date]);
}

- (void)commit {
    if (self.committed) return;
    self.committed = YES;
    self.nameField.holdsFocus = NO;
    self.nameField.delegate = nil;
    if (self.target && self.action)
        ((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
}

- (void)textDidChange:(NSNotification *)note __unused {
    NSString *clean = nil;
    NSDate *parsed = ParseDueFromText(self.nameField.string,
                                      self.typedBase ?: [NSDate date], &clean);
    self.cleanName = parsed ? clean : self.nameField.string;
    if (parsed) {
        self.dayValue = parsed;
        self.timeValue = parsed;
    }
}

- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)command {
    (void)view;
    if (command == @selector(insertNewline:)) {
        [self commit];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        self.cancelled = YES;
        [self commit];
        return YES;
    }
    return NO;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self.window makeFirstResponder:self.nameField];
        self.nameField.holdsFocus = YES;
    } else {
        self.nameField.holdsFocus = NO;
    }
}

@end

NSMenuItem *ComposeRowItem(NSString *name, NSDate *due,
                           id target, SEL action, id chipTarget,
                           SEL dayAction, CGFloat width) {
    ComposeRowView *v = [[ComposeRowView alloc]
        initWithFrame:NSMakeRect(0, 0, width, 22)];
    v.autoresizingMask = NSViewWidthSizable;
    [v.nameField setString:name ?: @""];
    v.typedBase = [NSDate date];
    v.cleanName = name ?: @"";
    v.dayValue = due;
    v.timeValue = due;
    v.target = target;
    v.action = action;
    v.chipTarget = chipTarget;
    v.dayAction = dayAction;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

@implementation CalendarRowView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;

    self.calendar = [[NSDatePicker alloc] init];
    self.calendar.datePickerStyle = NSDatePickerStyleClockAndCalendar;
    self.calendar.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.calendar.bordered = NO;
    self.calendar.drawsBackground = NO;
    self.calendar.translatesAutoresizingMaskIntoConstraints = NO;
    self.calendar.target = self;
    self.calendar.action = @selector(pick);

    [self addSubview:self.calendar];
    [NSLayoutConstraint activateConstraints:@[
        [self.calendar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.calendar.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

- (void)pick {
    if (self.target && self.action)
        ((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
}

@end

NSMenuItem *CalendarRowItem(NSDate *due, id target, SEL action, CGFloat width) {
    CalendarRowView *v = [[CalendarRowView alloc]
        initWithFrame:NSMakeRect(0, 0, width, 148)];
    v.autoresizingMask = NSViewWidthSizable;
    v.calendar.dateValue = due ?: [NSDate date];
    v.target = target;
    v.action = action;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

@interface CardView : HoverTipView
@property (copy) NSString *title;
@property (copy) NSString *code;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (copy) NSString *link;
@property (copy) NSString *zoom;
@property (strong) NSColor *bg;
@property (assign) CGFloat progress;
@property (assign) BOOL firstRow;
@property (assign) BOOL overPill;
@end

@implementation HoverTipView

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveAlways |
                     NSTrackingInVisibleRect
               owner:self userInfo:nil]];
}

- (void)cancelTip {
    [self.tipTimer invalidate];
    self.tipTimer = nil;
    if (self.tipShown) { self.tipShown = NO; TipHide(); }
}

- (void)scheduleTip {
    if (!self.tip.length || self.tipTimer || self.tipShown) return;
    __weak HoverTipView *weak = self;
    self.tipTimer = [NSTimer timerWithTimeInterval:0.45 repeats:NO
                                             block:^(NSTimer *t __unused) {
        HoverTipView *me = weak;
        me.tipTimer = nil;
        if (!me.window || !me.hovered) return;
        me.tipShown = YES;
        TipShowNear(me.tip, [me.window convertRectToScreen:
                        [me convertRect:me.bounds toView:nil]], NO);
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.tipTimer forMode:NSRunLoopCommonModes];
}

- (void)syncHoverAt:(NSPoint)pt __unused {
    if (!self.hovered) { self.hovered = YES; self.needsDisplay = YES; }
    [self scheduleTip];
}

- (void)mouseMoved:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e __unused {
    self.hovered = NO;
    self.needsDisplay = YES;
    [self cancelTip];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) { self.hovered = NO; [self cancelTip]; }
}

@end

@implementation CardView

- (NSRect)boxRect {
    CGFloat top = self.firstRow ? kRowInset : kRowInset / 2;
    return NSMakeRect(kRowInset, kRowInset / 2,
                      NSWidth(self.bounds) - kRowInset * 2,
                      NSHeight(self.bounds) - kRowInset / 2 - top);
}

- (void)syncHoverAt:(NSPoint)pt {
    BOOL onPill = self.zoom.length && NSPointInRect(pt, [self pillRect]);
    if (onPill != self.overPill || !self.hovered) {
        self.overPill = onPill;
        self.hovered = YES;
        self.needsDisplay = YES;
    }
    [self scheduleTip];
}

- (NSRect)pillRect {
    if (!self.zoom.length) return NSZeroRect;
    NSRect box = [self boxRect];
    NSDictionary *f = @{ NSFontAttributeName:
        [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold] };
    CGFloat w = ceil([@"zoom" sizeWithAttributes:f].width) + 25;
    CGFloat h = 15;
    CGFloat x = NSMaxX(box) - kTextInset - w;
    CGFloat y = NSMinY(box) + (NSHeight(box) * 0.5 - h) * 0.5 + 1;
    if (x < NSMinX(box) + 8) x = NSMinX(box) + 8;
    if (y < NSMinY(box) + 3) y = NSMinY(box) + 3;
    return NSMakeRect(x, y, w, h);
}

- (void)mouseExited:(NSEvent *)e {
    self.overPill = NO;
    [super mouseExited:e];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) self.overPill = NO;
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    NSString *target = (self.zoom.length && NSPointInRect(pt, [self pillRect]))
                     ? self.zoom : self.link;
    [self cancelTip];
    [self.enclosingMenuItem.menu cancelTracking];
    if (target.length) {
        NSURL *u = [NSURL URLWithString:target];
        if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    }
}

- (void)drawRect:(NSRect)dirty {
    NSRect box = [self boxRect];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:box
                                                      xRadius:kRowRadius
                                                      yRadius:kRowRadius];
    NSColor *fill = self.bg;
    if (self.hovered && !self.overPill) {
        NSColor *c = [self.bg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        CGFloat hue = 0, sat = 0, bri = 0, alp = 1;
        [c getHue:&hue saturation:&sat brightness:&bri alpha:&alp];
        fill = [NSColor colorWithHue:hue
                          saturation:MIN(1.0, sat * 1.75 + 0.05)
                          brightness:MAX(0.0, bri * 0.985)
                               alpha:1.0];
    }
    [fill setFill];
    [p fill];

    if (self.progress > 0) {
        NSRect track = NSMakeRect(NSMinX(box) + kTextInset, NSMinY(box) + 9,
                                  NSWidth(box) - kTextInset * 2, 5);
        [[NSColor colorWithWhite:0.0 alpha:0.16] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:track
                                         xRadius:2.5 yRadius:2.5] fill];
        NSRect run = track;
        run.size.width = MAX(5, NSWidth(track) * MIN(1.0, self.progress));
        [[NSColor colorWithWhite:0.0 alpha:0.62] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:run
                                         xRadius:2.5 yRadius:2.5] fill];
    }

    NSDictionary *tAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    NSDictionary *sAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.13 alpha:1.0]
    };

    CGFloat topY = NSMaxY(box) - 22;
    CGFloat botY = NSMinY(box) + (self.progress > 0 ? 19 : 7);

    NSMutableAttributedString *head = [[NSMutableAttributedString alloc]
        initWithString:self.title attributes:tAttr];
    if (self.code.length) {
        NSDictionary *cAttr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.26 alpha:1.0]
        };
        [head appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  (%@)", self.code] attributes:cAttr]];
    }
    if (!CardHasDetail(self.when, self.room, self.zoom)) {
        [head drawAtPoint:NSMakePoint(NSMinX(box) + kTextInset,
                                      NSMidY(box) - [head size].height * 0.5)];
        return;
    }

    [head drawAtPoint:NSMakePoint(NSMinX(box) + kTextInset, topY)];
    [self.when drawAtPoint:NSMakePoint(NSMinX(box) + kTextInset, botY)
            withAttributes:sAttr];

    if (self.zoom.length) {
        NSRect pill = [self pillRect];
        NSBezierPath *pp = [NSBezierPath bezierPathWithRoundedRect:pill
                                                           xRadius:8.5 yRadius:8.5];
        [[NSColor colorWithWhite:self.overPill ? 0.16 : 0.44 alpha:1.0] setFill];
        [pp fill];
        NSDictionary *zAttr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        NSSize zs = [@"zoom" sizeWithAttributes:zAttr];
        CGFloat tx = NSMinX(pill) + 8;
        [@"zoom" drawAtPoint:NSMakePoint(tx, NSMidY(pill) - zs.height / 2 + 0.5)
              withAttributes:zAttr];
        DrawSymbol(@"arrow.up.right", 8.5, [NSColor whiteColor],
                   NSMakeRect(tx + zs.width + 2, NSMinY(pill), 11, NSHeight(pill)));
    } else {
        NSSize rs = [self.room sizeWithAttributes:sAttr];
        [self.room drawAtPoint:NSMakePoint(NSMaxX(box) - kTextInset - rs.width, botY)
                withAttributes:sAttr];
    }
}

@end

NSFont *DueFont(BOOL late) {
    return [NSFont monospacedDigitSystemFontOfSize:11
                                            weight:late ? NSFontWeightBold
                                                        : NSFontWeightMedium];
}

NSFont *NameFont(void) {
    return [NSFont systemFontOfSize:12];
}

@implementation AssignmentView

- (NSRect)rowRect {
    return NSMakeRect(kRowInset, 1, NSWidth(self.bounds) - kRowInset * 2,
                      NSHeight(self.bounds) - 2);
}

- (BOOL)deletable {
    return [self.item[@"task"] boolValue] && self.deleteAction != NULL;
}

- (NSRect)deleteRect {
    if (!self.deletable) return NSZeroRect;
    NSRect c = [self circleRect];
    return NSMakeRect(NSMinX(c) - 8 - 13, NSMidY(c) - 6.5, 13, 13);
}

- (NSRect)circleRect {
    NSRect r = [self rowRect];
    CGFloat d = 13;
    return NSMakeRect(NSMaxX(r) - d - kTextInset, NSMidY(r) - d / 2, d, d);
}

- (void)syncHoverAt:(NSPoint)pt {
    BOOL on = NSPointInRect(pt, NSInsetRect([self circleRect], -5, -4));
    BOOL kill = self.deletable &&
                NSPointInRect(pt, NSInsetRect([self deleteRect], -3, -4));
    if (on != self.overCircle || kill != self.overDelete) {
        self.overCircle = on;
        self.overDelete = kill;
        self.needsDisplay = YES;
    }
    [super syncHoverAt:pt];
}

- (void)mouseExited:(NSEvent *)e {
    self.overCircle = NO;
    self.overDelete = NO;
    [super mouseExited:e];
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    if (self.deletable &&
        NSPointInRect(pt, NSInsetRect([self deleteRect], -3, -4))) {
        [self cancelTip];
        ((void (*)(id, SEL, id))objc_msgSend)(self.target, self.deleteAction, self);
        return;
    }
    if (NSPointInRect(pt, NSInsetRect([self circleRect], -5, -4))) {
        if (self.target && self.toggleAction)
            ((void (*)(id, SEL, id))objc_msgSend)(self.target, self.toggleAction, self);
        return;
    }
    if (!self.link.length) return;
    [self cancelTip];
    [self.enclosingMenuItem.menu cancelTracking];
    NSURL *u = [NSURL URLWithString:self.link];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (void)drawCircle {
    NSRect c = [self circleRect];
    NSColor *tint = self.rail ?: [NSColor tertiaryLabelColor];

    if (self.hovered || self.done) {
        NSColor *ink = self.hovered ? [NSColor alternateSelectedControlTextColor] : tint;
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(c, 1, 1)];
        ring.lineWidth = 1.5;
        [[ink colorWithAlphaComponent:self.overCircle ? 1.0 : 0.6] setStroke];
        [ring stroke];
    }

    [[tint colorWithAlphaComponent:self.done ? 0.4 : 1.0] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(c, 3, 3)] fill];
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return self.link.length ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole;
}

- (NSString *)accessibilityLabel {
    return TipJoin(@[self.due ?: @"", self.name ?: @"",
                     self.done ? @"completed" : @""]);
}

- (NSArray<NSAccessibilityCustomAction *> *)accessibilityCustomActions {
    if (!self.target || !self.toggleAction) return @[];
    __weak AssignmentView *weak = self;
    NSString *title = self.done ? @"mark not done" : @"mark done";
    return @[[[NSAccessibilityCustomAction alloc] initWithName:title handler:^BOOL{
        AssignmentView *me = weak;
        if (!me || !me.target || !me.toggleAction) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(me.target, me.toggleAction, me);
        return YES;
    }]];
}


- (void)drawRect:(NSRect)dirty __unused {
    if (self.hovered) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:[self rowRect]
                                                          xRadius:kRowRadius
                                                          yRadius:kRowRadius];
        [[NSColor selectedContentBackgroundColor] setFill];
        [p fill];
    }

    NSColor *dueColor = self.hovered
        ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.8]
        : (self.late ? [NSColor systemRedColor] : [NSColor secondaryLabelColor]);
    NSDictionary *dueAttr = @{
        NSFontAttributeName: DueFont(self.late),
        NSForegroundColorAttributeName: dueColor
    };
    NSMutableDictionary *nameAttr = [@{
        NSFontAttributeName: NameFont(),
        NSForegroundColorAttributeName: self.hovered
            ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]
    } mutableCopy];
    if (self.done) {
        nameAttr[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        if (!self.hovered)
            nameAttr[NSForegroundColorAttributeName] = [NSColor tertiaryLabelColor];
    }

    NSMutableParagraphStyle *clip = [[NSMutableParagraphStyle alloc] init];
    clip.lineBreakMode = NSLineBreakByTruncatingTail;
    nameAttr[NSParagraphStyleAttributeName] = clip;

    NSMutableAttributedString *due =
        [[NSMutableAttributedString alloc] initWithString:self.due ?: @""
                                              attributes:dueAttr];
    NSRange gap = [self.due rangeOfString:@" "];
    if (gap.location != NSNotFound) {
        NSRange tail = NSMakeRange(gap.location,
                                   self.due.length - gap.location);
        [due addAttribute:NSForegroundColorAttributeName
                    value:[dueColor colorWithAlphaComponent:0.55] range:tail];
    }

    NSSize ds = due.size;
    NSSize ns = [self.name sizeWithAttributes:nameAttr];
    CGFloat nameX = NSMinX([self rowRect]) + kTextInset;
    BOOL showKill = self.hovered && self.deletable;
    CGFloat dueRight = (showKill ? NSMinX([self deleteRect]) : NSMinX([self circleRect]))
                     - 8;

    [due drawAtPoint:NSMakePoint(dueRight - ceil(ds.width),
                                 NSMidY(self.bounds) - ds.height / 2)];

    CGFloat nameW = dueRight - self.dueWidth - kDueColumnGap - nameX;
    if (nameW > 0)
        [self.name drawInRect:NSMakeRect(nameX, NSMidY(self.bounds) - ns.height / 2,
                                         nameW, ns.height)
               withAttributes:nameAttr];
    if (showKill)
        DrawSymbol(@"xmark", 9,
                   [(self.overDelete ? [NSColor systemRedColor]
                                     : [NSColor alternateSelectedControlTextColor])
                       colorWithAlphaComponent:self.overDelete ? 1.0 : 0.65],
                   [self deleteRect]);
    [self drawCircle];
}

@end

NSMenuItem *AssignmentItem(NSDictionary *item, NSString *due, NSString *name,
                           NSString *link, NSString *tip, BOOL late, BOOL done,
                           NSColor *rail, CGFloat dueWidth, CGFloat width,
                           id target, SEL toggleAction, SEL deleteAction) {
    AssignmentView *v = [[AssignmentView alloc]
        initWithFrame:NSMakeRect(0, 0, width, 22)];
    v.autoresizingMask = NSViewWidthSizable;
    v.due = due; v.name = name; v.link = link; v.tip = tip; v.late = late;
    v.dueWidth = dueWidth;
    v.item = item; v.done = done; v.rail = rail;
    v.target = target; v.toggleAction = toggleAction;
    v.deleteAction = deleteAction;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
                            NSString *link, NSString *zoom, NSString *tip,
                            NSColor *bg, CGFloat progress, BOOL first, CGFloat width) {
    CardView *v = [[CardView alloc]
        initWithFrame:NSMakeRect(0, 0, width,
                                 CardHeight(when, room, zoom, progress, first))];
    v.autoresizingMask = NSViewWidthSizable;
    v.title = title; v.code = code; v.when = when; v.room = room;
    v.link = link; v.zoom = zoom; v.tip = tip; v.bg = bg; v.progress = progress;
    v.firstRow = first;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

@implementation FooterView

- (NSDictionary *)quitAttributes {
    return @{ NSFontAttributeName: [NSFont systemFontOfSize:13] };
}

- (NSRect)quitRect {
    NSSize s = [@"quit" sizeWithAttributes:[self quitAttributes]];
    return NSMakeRect(kRowInset, NSMidY(self.bounds) - 11,
                      ceil(s.width) + kTextInset * 2, 22);
}

- (NSRect)gearRect {
    return NSMakeRect(NSMaxX(self.bounds) - kRowInset - kTextInset - 20,
                      NSMidY(self.bounds) - 9, 20, 18);
}

- (NSRect)plusRect {
    return NSOffsetRect([self gearRect], -28, 0);
}

- (NSRect)refreshRect {
    return NSOffsetRect([self plusRect], -28, 0);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveAlways |
                     NSTrackingInVisibleRect
               owner:self userInfo:nil]];
}

- (void)syncAt:(NSPoint)pt {
    BOOL refresh = NSPointInRect(pt, NSInsetRect([self refreshRect], -4, -4));
    BOOL plus = NSPointInRect(pt, NSInsetRect([self plusRect], -4, -4));
    BOOL gear = NSPointInRect(pt, NSInsetRect([self gearRect], -4, -4));
    BOOL quit = NSPointInRect(pt, [self quitRect]);
    if (refresh != self.overRefresh || gear != self.overGear ||
        plus != self.overPlus || quit != self.overQuit || !self.hovered) {
        self.overRefresh = refresh;
        self.overPlus = plus;
        self.overGear = gear;
        self.overQuit = quit;
        self.hovered = YES;
        self.needsDisplay = YES;
    }
}

- (void)mouseMoved:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e {
    self.hovered = NO;
    self.overRefresh = NO;
    self.overPlus = NO;
    self.overGear = NO;
    self.overQuit = NO;
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    SEL sel = NULL;
    if (NSPointInRect(pt, NSInsetRect([self refreshRect], -4, -4))) {
        sel = self.refreshAction;
    } else if (NSPointInRect(pt, NSInsetRect([self plusRect], -4, -4))) {
        sel = self.plusAction;
    } else if (NSPointInRect(pt, NSInsetRect([self gearRect], -4, -4))) {
        [self.enclosingMenuItem.menu cancelTracking];
        sel = self.settingsAction;
    } else {
        [self.enclosingMenuItem.menu cancelTracking];
        if (NSPointInRect(pt, [self quitRect])) sel = self.quitAction;
    }
    if (self.target && sel) ((void (*)(id, SEL))objc_msgSend)(self.target, sel);
}

- (void)drawIcon:(NSImage *)icon inRect:(NSRect)r lit:(BOOL)lit {
    if (lit) {
        NSBezierPath *bgp = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -4, -2)
                                                            xRadius:5 yRadius:5];
        [[NSColor selectedContentBackgroundColor] setFill];
        [bgp fill];
    }
    if (!icon) return;
    NSSize sz = icon.size;
    [icon drawInRect:NSMakeRect(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2,
                                sz.width, sz.height)
            fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
}

- (void)drawRect:(NSRect)dirty {
    BOOL quitLit = self.overQuit;
    NSRect quit = [self quitRect];

    if (quitLit) {
        NSBezierPath *hp = [NSBezierPath bezierPathWithRoundedRect:quit
                                                           xRadius:kRowRadius
                                                           yRadius:kRowRadius];
        [[NSColor selectedContentBackgroundColor] setFill];
        [hp fill];
    }

    NSMutableDictionary *a = [[self quitAttributes] mutableCopy];
    a[NSForegroundColorAttributeName] = quitLit
        ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
    NSSize qs = [@"quit" sizeWithAttributes:a];
    [@"quit" drawAtPoint:NSMakePoint(NSMinX(quit) + kTextInset,
                                     NSMidY(quit) - qs.height / 2)
          withAttributes:a];

    if (self.status.length) {
        NSDictionary *sa = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10.5],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        };
        NSSize ss = [self.status sizeWithAttributes:sa];
        [self.status drawAtPoint:NSMakePoint(NSMinX([self refreshRect]) - 12 - ss.width,
                                             NSMidY(self.bounds) - ss.height / 2)
                  withAttributes:sa];
    }

    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
        isEqualToString:NSAppearanceNameDarkAqua];

    [self drawIcon:RefreshIconImage(dark || self.overRefresh)
            inRect:[self refreshRect] lit:self.overRefresh];
    [self drawIcon:PlusIconImage(dark || self.overPlus)
            inRect:[self plusRect] lit:self.overPlus];
    [self drawIcon:GearIconImage(dark || self.overGear)
            inRect:[self gearRect] lit:self.overGear];
}

@end
