#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "views.h"
#import "icons.h"
#import "schedule.h"
#import "store.h"

const CGFloat kDueColumnGap = 12.0;
const CGFloat kDoneCircleWidth = 26.0;

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

static CGFloat CardHeight(NSString *when, NSString *room, NSString *zoom) {
    return CardHasDetail(when, room, zoom) ? 52.0 : 34.0;
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

@interface CardView : HoverTipView
@property (copy) NSString *title;
@property (copy) NSString *code;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (copy) NSString *link;
@property (copy) NSString *zoom;
@property (strong) NSColor *bg;
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
    NSRect box = NSInsetRect(self.bounds, 7, 3);
    NSDictionary *f = @{ NSFontAttributeName:
        [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold] };
    CGFloat w = ceil([@"Zoom" sizeWithAttributes:f].width) + 25;
    CGFloat h = 15;
    CGFloat x = NSMaxX(box) - 8 - w;
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
    NSRect box = NSInsetRect(self.bounds, 7, 3);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:box xRadius:7 yRadius:7];
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

    NSDictionary *tAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    NSDictionary *sAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.13 alpha:1.0]
    };

    CGFloat topY = NSMaxY(box) - 22;
    CGFloat botY = NSMinY(box) + 7;

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
        [head drawAtPoint:NSMakePoint(NSMinX(box) + 9,
                                      NSMidY(box) - [head size].height * 0.5)];
        return;
    }

    [head drawAtPoint:NSMakePoint(NSMinX(box) + 9, topY)];
    [self.when drawAtPoint:NSMakePoint(NSMinX(box) + 9, botY) withAttributes:sAttr];

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
        NSSize zs = [@"Zoom" sizeWithAttributes:zAttr];
        CGFloat tx = NSMinX(pill) + 8;
        [@"Zoom" drawAtPoint:NSMakePoint(tx, NSMidY(pill) - zs.height / 2 + 0.5)
              withAttributes:zAttr];
        DrawSymbol(@"arrow.up.right", 8.5, [NSColor whiteColor],
                   NSMakeRect(tx + zs.width + 2, NSMinY(pill), 11, NSHeight(pill)));
    } else {
        NSSize rs = [self.room sizeWithAttributes:sAttr];
        [self.room drawAtPoint:NSMakePoint(NSMaxX(box) - 9 - rs.width, botY)
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
    return NSMakeRect(5, 1, NSWidth(self.bounds) - 10, NSHeight(self.bounds) - 2);
}

- (NSRect)circleRect {
    NSRect r = [self rowRect];
    CGFloat d = 13;
    return NSMakeRect(NSMaxX(r) - d - 9, NSMidY(r) - d / 2, d, d);
}

- (void)syncHoverAt:(NSPoint)pt {
    BOOL on = NSPointInRect(pt, NSInsetRect([self circleRect], -5, -4));
    if (on != self.overCircle) {
        self.overCircle = on;
        self.needsDisplay = YES;
    }
    [super syncHoverAt:pt];
}

- (void)mouseExited:(NSEvent *)e {
    self.overCircle = NO;
    [super mouseExited:e];
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
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
    if (!self.hovered && !self.done) return;
    NSRect c = [self circleRect];
    NSColor *ink = self.hovered ? [NSColor alternateSelectedControlTextColor]
                                : [NSColor tertiaryLabelColor];
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(c, 1, 1)];
    ring.lineWidth = 1.5;
    [[ink colorWithAlphaComponent:self.overCircle ? 1.0 : 0.65] setStroke];
    [ring stroke];
    if (!self.done) return;
    [[ink colorWithAlphaComponent:0.9] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(c, 4, 4)] fill];
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
    NSString *title = self.done ? @"Mark not done" : @"Mark done";
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
                                                          xRadius:5 yRadius:5];
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

    NSSize ds = [self.due sizeWithAttributes:dueAttr];
    NSSize ns = [self.name sizeWithAttributes:nameAttr];
    CGFloat x = NSMinX([self rowRect]) + 9;
    [self.due drawAtPoint:NSMakePoint(x, NSMidY(self.bounds) - ds.height / 2)
           withAttributes:dueAttr];

    CGFloat nameX = x + self.dueWidth + kDueColumnGap;
    CGFloat nameW = NSMinX([self circleRect]) - 7 - nameX;
    if (nameW > 0)
        [self.name drawInRect:NSMakeRect(nameX, NSMidY(self.bounds) - ns.height / 2,
                                         nameW, ns.height)
               withAttributes:nameAttr];
    [self drawCircle];
}

@end

NSMenuItem *AssignmentItem(NSDictionary *item, NSString *due, NSString *name,
                           NSString *link, NSString *tip, BOOL late, BOOL done,
                           CGFloat dueWidth, CGFloat width,
                           id target, SEL toggleAction) {
    AssignmentView *v = [[AssignmentView alloc]
        initWithFrame:NSMakeRect(0, 0, width, 22)];
    v.autoresizingMask = NSViewWidthSizable;
    v.due = due; v.name = name; v.link = link; v.tip = tip; v.late = late;
    v.dueWidth = dueWidth;
    v.item = item; v.done = done;
    v.target = target; v.toggleAction = toggleAction;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
                            NSString *link, NSString *zoom, NSString *tip,
                            NSColor *bg, CGFloat width) {
    CardView *v = [[CardView alloc]
        initWithFrame:NSMakeRect(0, 0, width, CardHeight(when, room, zoom))];
    v.autoresizingMask = NSViewWidthSizable;
    v.title = title; v.code = code; v.when = when; v.room = room;
    v.link = link; v.zoom = zoom; v.tip = tip; v.bg = bg;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

@implementation FooterView

- (NSDictionary *)quitAttributes {
    return @{ NSFontAttributeName: [NSFont systemFontOfSize:13] };
}

- (NSRect)quitRect {
    NSSize s = [@"Quit" sizeWithAttributes:[self quitAttributes]];
    return NSMakeRect(5, NSMidY(self.bounds) - 11, ceil(s.width) + 18, 22);
}

- (NSRect)gearRect {
    return NSMakeRect(NSMaxX(self.bounds) - 34, NSMidY(self.bounds) - 9, 20, 18);
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
        [self.enclosingMenuItem.menu cancelTracking];
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
                                                           xRadius:6 yRadius:6];
        [[NSColor selectedContentBackgroundColor] setFill];
        [hp fill];
    }

    NSMutableDictionary *a = [[self quitAttributes] mutableCopy];
    a[NSForegroundColorAttributeName] = quitLit
        ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
    NSSize qs = [@"Quit" sizeWithAttributes:a];
    [@"Quit" drawAtPoint:NSMakePoint(NSMinX(quit) + 9, NSMidY(quit) - qs.height / 2)
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
