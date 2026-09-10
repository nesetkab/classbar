#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "icons.h"

static NSString *SchedulePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/schedule.json"];
}

static NSString *CachePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Caches/classbar/upcoming.json"];
}

static int ParseClock(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return -1;
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if (parts.count != 2) return -1;
    int h = [parts[0] intValue], m = [parts[1] intValue];
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
}

@interface Schedule : NSObject
@property (strong) NSArray *byDay;
@property (copy)   NSString *canvasHome;
@property (assign) int termStart;
@property (assign) int termEnd;
@property (copy)   NSString *beforeLabel;
@property (copy)   NSString *canvasFeed;
@property (copy)   NSString *loadError;
@end

@implementation Schedule

+ (instancetype)loadFromDisk {
    Schedule *s = [[Schedule alloc] init];
    s.canvasHome = @"https://canvas.instructure.com/";
    s.termStart = 0;
    s.termEnd = 99999999;
    s.beforeLabel = @"Term hasn't started";

    NSData *d = [NSData dataWithContentsOfFile:SchedulePath()];
    if (!d) {
        s.loadError = @"No schedule.json";
        s.byDay = @[@[], @[], @[], @[], @[], @[], @[]];
        return s;
    }
    NSError *err = nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
    if (![root isKindOfClass:[NSDictionary class]]) {
        s.loadError = err ? @"schedule.json is not valid JSON" : @"schedule.json is malformed";
        s.byDay = @[@[], @[], @[], @[], @[], @[], @[]];
        return s;
    }

    if ([root[@"canvasHome"] isKindOfClass:[NSString class]]) s.canvasHome = root[@"canvasHome"];
    if ([root[@"canvasFeed"] isKindOfClass:[NSString class]]) s.canvasFeed = root[@"canvasFeed"];
    NSDictionary *term = root[@"term"];
    if ([term isKindOfClass:[NSDictionary class]]) {
        if ([term[@"start"] isKindOfClass:[NSNumber class]]) s.termStart = [term[@"start"] intValue];
        if ([term[@"end"] isKindOfClass:[NSNumber class]]) s.termEnd = [term[@"end"] intValue];
        if ([term[@"beforeLabel"] isKindOfClass:[NSString class]]) s.beforeLabel = term[@"beforeLabel"];
    }

    NSMutableArray *buckets = [NSMutableArray arrayWithCapacity:7];
    for (int i = 0; i < 7; i++) [buckets addObject:[NSMutableArray array]];

    for (NSDictionary *c in root[@"classes"]) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        int st = ParseClock(c[@"start"]), en = ParseClock(c[@"end"]);
        if (st < 0 || en < 0 || en <= st) continue;
        if (![c[@"name"] isKindOfClass:[NSString class]]) continue;
        NSDictionary *entry = @{
            @"name": c[@"name"],
            @"code": [c[@"code"] isKindOfClass:[NSString class]] ? c[@"code"] : @"",
            @"room": [c[@"room"] isKindOfClass:[NSString class]] ? c[@"room"] : @"",
            @"start": @(st),
            @"end": @(en),
            @"canvas": [c[@"canvas"] isKindOfClass:[NSString class]] ? c[@"canvas"] : @"",
            @"zoom": [c[@"zoom"] isKindOfClass:[NSString class]] ? c[@"zoom"] : @""
        };
        for (NSNumber *dn in c[@"days"]) {
            if (![dn isKindOfClass:[NSNumber class]]) continue;
            int day = dn.intValue;
            if (day < 0 || day > 6) continue;
            [buckets[day] addObject:entry];
        }
    }

    NSSortDescriptor *byStart = [NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES];
    for (int i = 0; i < 7; i++) [buckets[i] sortUsingDescriptors:@[byStart]];
    s.byDay = buckets;
    return s;
}

@end

static NSString *DUR(int m) {
    if (m < 60) return [NSString stringWithFormat:@"%dm", m];
    int h = m / 60, r = m % 60;
    return r ? [NSString stringWithFormat:@"%dh %dm", h, r]
             : [NSString stringWithFormat:@"%dh", h];
}

static const char * const kDayName[7] = {
    "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"
};

static NSString *HHMMshort(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d%s", h, mm, h24 >= 12 ? "p" : "a"];
}

static NSDictionary *cb_notice(NSString *title, NSString *when) {
    return @{ @"title": title, @"code": @"", @"when": when ?: @"",
              @"room": @"", @"link": @"", @"zoom": @"", @"now": @NO,
              @"notice": @YES };
}

static NSString *cb_next_tip(Schedule *s, int day) {
    for (int k = 1; k <= 7; k++) {
        int nd = (day + k) % 7;
        NSArray *list = s.byDay[nd];
        if (!list.count) continue;
        NSDictionary *c = list[0];
        NSMutableString *t = [NSMutableString stringWithFormat:@"Next: %@", c[@"name"]];
        if ([c[@"code"] length]) [t appendFormat:@" (%@)", c[@"code"]];
        [t appendFormat:@"\n%.3s %@", kDayName[nd], HHMMshort([c[@"start"] intValue])];
        if ([c[@"room"] length]) [t appendFormat:@"\n%@", c[@"room"]];
        return t;
    }
    return @"";
}

static NSDictionary *cb_done(Schedule *s, int day) {
    NSMutableDictionary *m = [cb_notice(@"done for the day! :3", @"") mutableCopy];
    m[@"tip"] = cb_next_tip(s, day);
    m[@"done"] = @YES;
    return m;
}

static NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count) {
    NSMutableArray *out = [NSMutableArray array];
    if (s.loadError)
        return @[cb_notice(s.loadError, @"Add one to Application Support/classbar")];
    if (ymd < s.termStart) return @[cb_notice(@"Term hasn't started", s.beforeLabel)];
    if (ymd > s.termEnd)   return @[cb_notice(@"Term is over", @"")];

    int d = day, after = mins, guard = 0;
    BOOL checkNow = YES;

    while ((int)out.count < count && guard++ < 24) {
        NSDictionary *hit = nil;
        BOOL now = NO;

        if (checkNow) {
            for (NSDictionary *c in s.byDay[d]) {
                int st = [c[@"start"] intValue], en = [c[@"end"] intValue];
                if (mins >= st && mins < en) { hit = c; now = YES; break; }
            }
            checkNow = NO;
        }
        if (!hit)
            for (NSDictionary *c in s.byDay[d])
                if ([c[@"start"] intValue] > after) { hit = c; break; }

        if (hit) {
            int st = [hit[@"start"] intValue], en = [hit[@"end"] intValue];
            NSString *when;
            if (now)
                when = [NSString stringWithFormat:@"%@ • %@ left", HHMMshort(st), DUR(en - mins)];
            else if (d == day)
                when = [NSString stringWithFormat:@"%@ • in %@", HHMMshort(st), DUR(st - mins)];
            else
                when = [NSString stringWithFormat:@"%.3s %@", kDayName[d], HHMMshort(st)];

            [out addObject:@{
                @"title": hit[@"name"],
                @"code": hit[@"code"] ?: @"",
                @"when": when,
                @"room": [hit[@"room"] length] ? hit[@"room"] : @"",
                @"link": [hit[@"canvas"] length] ? hit[@"canvas"] : s.canvasHome,
                @"zoom": hit[@"zoom"] ?: @"",
                @"now": @(now)
            }];
            after = st;
            continue;
        }

        if (d == day && [s.byDay[day] count]) {
            [out addObject:cb_done(s, day)];
            break;
        }

        BOOL rolled = NO;
        for (int k = 1; k <= 7 && !rolled; k++) {
            int nd = (d + k) % 7;
            if ([s.byDay[nd] count]) { d = nd; after = -1; rolled = YES; }
        }
        if (!rolled) break;
    }
    if (!out.count) return @[cb_notice(@"No classes", @"")];
    return out;
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

static CGFloat CardHeight(NSString *when, NSString *room, NSString *zoom) {
    return CardHasDetail(when, room, zoom) ? 52.0 : 34.0;
}

static NSPanel *gTipPanel;
static NSTextField *gTipLabel;

static void TipHide(void) {
    [gTipPanel orderOut:nil];
}

static void TipShow(NSString *text, NSRect anchor) {
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

    NSRect frame = NSMakeRect(NSMinX(anchor) - 8 - (ts.width + 18),
                              NSMidY(anchor) - (ts.height + 12) * 0.5,
                              ts.width + 18, ts.height + 12);

    NSScreen *scr = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens])
        if (NSIntersectsRect(s.frame, anchor)) { scr = s; break; }
    NSRect vis = scr.visibleFrame;
    if (NSMinX(frame) < NSMinX(vis) + 6) frame.origin.x = NSMaxX(anchor) + 8;
    if (NSMaxX(frame) > NSMaxX(vis) - 6) frame.origin.x = NSMaxX(vis) - 6 - NSWidth(frame);
    if (NSMinY(frame) < NSMinY(vis) + 6) frame.origin.y = NSMinY(vis) + 6;
    if (NSMaxY(frame) > NSMaxY(vis) - 6) frame.origin.y = NSMaxY(vis) - 6 - NSHeight(frame);

    [gTipPanel setFrame:frame display:NO];
    [gTipPanel orderFrontRegardless];
}

@interface CardView : NSView
@property (copy) NSString *title;
@property (copy) NSString *code;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (copy) NSString *link;
@property (copy) NSString *zoom;
@property (copy) NSString *tip;
@property (strong) NSColor *bg;
@property (strong) NSTimer *tipTimer;
@property (assign) BOOL tipShown;
@property (assign) BOOL hovered;
@property (assign) BOOL overPill;
@end

@implementation CardView

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
    __weak CardView *weak = self;
    self.tipTimer = [NSTimer timerWithTimeInterval:0.45 repeats:NO
                                             block:^(NSTimer *t __unused) {
        CardView *me = weak;
        me.tipTimer = nil;
        if (!me.window || !me.hovered) return;
        me.tipShown = YES;
        TipShow(me.tip, [me.window convertRectToScreen:
                            [me convertRect:me.bounds toView:nil]]);
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.tipTimer forMode:NSRunLoopCommonModes];
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

- (void)mouseMoved:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
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

- (void)mouseEntered:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e {
    self.hovered = NO; self.overPill = NO; self.needsDisplay = YES;
    [self cancelTip];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) { self.hovered = NO; self.overPill = NO; [self cancelTip]; }
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

static NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
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

static NSISO8601DateFormatter *ISOFormatter(void) {
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
    return f;
}

static NSArray *IcsUnfold(NSString *text) {
    NSArray *raw = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@"\n\r"]];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in raw) {
        if (out.count && ([line hasPrefix:@" "] || [line hasPrefix:@"\t"]))
            out[out.count - 1] = [out.lastObject
                stringByAppendingString:[line substringFromIndex:1]];
        else
            [out addObject:line];
    }
    return out;
}

static NSString *IcsUnescape(NSString *v) {
    NSString *s = [v stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\N" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\," withString:@","];
    s = [s stringByReplacingOccurrencesOfString:@"\\;" withString:@";"];
    s = [s stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
    return [s stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSDate *IcsDate(NSString *tzid, NSString *value) {
    if (value.length < 8) return nil;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    if (value.length < 15) {
        f.dateFormat = @"yyyyMMdd";
        f.timeZone = [NSTimeZone localTimeZone];
        return [f dateFromString:[value substringToIndex:8]];
    }
    f.dateFormat = @"yyyyMMdd'T'HHmmss";
    if ([value hasSuffix:@"Z"])
        f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    else
        f.timeZone = (tzid.length ? [NSTimeZone timeZoneWithName:tzid] : nil)
                   ?: [NSTimeZone localTimeZone];
    return [f dateFromString:[value substringToIndex:15]];
}

static NSString *FirstGroup(NSString *text, NSString *pattern) {
    if (!text.length) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                       options:0
                                                                         error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0
                                               range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    return [text substringWithRange:[m rangeAtIndex:1]];
}

static NSString *AssignmentURL(NSString *raw, NSString *home) {
    NSString *course = FirstGroup(raw, @"course_([0-9]+)");
    NSString *assignment = FirstGroup(raw, @"assignment_([0-9]+)");
    if (!course || !assignment || !home.length) return raw;
    NSString *base = [home hasSuffix:@"/"] ? home : [home stringByAppendingString:@"/"];
    return [NSString stringWithFormat:@"%@courses/%@/assignments/%@",
                                      base, course, assignment];
}

static void SplitSummary(NSString *summary, NSString **name, NSString **course) {
    *name = summary;
    *course = nil;
    if (![summary hasSuffix:@"]"]) return;
    NSRange open = [summary rangeOfString:@"[" options:NSBackwardsSearch];
    if (open.location == NSNotFound) return;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange inner = NSMakeRange(open.location + 1,
                                summary.length - open.location - 2);
    NSString *tail = [[summary substringWithRange:inner] stringByTrimmingCharactersInSet:ws];
    NSString *head = [[summary substringToIndex:open.location]
                      stringByTrimmingCharactersInSet:ws];
    if (!head.length || !tail.length) return;
    *name = head;
    *course = tail;
}

static NSArray *IcsEvents(NSString *text) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableDictionary *event = nil;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *line in IcsUnfold(text)) {
        NSRange colon = [line rangeOfString:@":"];
        NSString *head = colon.location == NSNotFound ? line
                       : [line substringToIndex:colon.location];
        NSString *value = colon.location == NSNotFound ? @""
                        : [line substringFromIndex:colon.location + 1];
        NSArray *parts = [head componentsSeparatedByString:@";"];
        NSString *name = [parts[0] uppercaseString];

        if ([name isEqualToString:@"BEGIN"] && [value hasPrefix:@"VEVENT"]) {
            event = [NSMutableDictionary dictionary];
            continue;
        }
        if ([name isEqualToString:@"END"] && [value hasPrefix:@"VEVENT"]) {
            if (event) [out addObject:event];
            event = nil;
            continue;
        }
        if (!event) continue;

        if ([name isEqualToString:@"DTSTART"] || [name isEqualToString:@"DTEND"]) {
            NSString *tzid = nil;
            for (NSUInteger i = 1; i < parts.count; i++)
                if ([[parts[i] uppercaseString] hasPrefix:@"TZID="])
                    tzid = [parts[i] substringFromIndex:5];
            NSDate *d = IcsDate(tzid, [value stringByTrimmingCharactersInSet:ws]);
            if (d) event[name] = d;
        } else if ([name isEqualToString:@"SUMMARY"] ||
                   [name isEqualToString:@"LOCATION"] ||
                   [name isEqualToString:@"UID"] ||
                   [name isEqualToString:@"URL"]) {
            event[name] = IcsUnescape(value);
        } else if ([name isEqualToString:@"RRULE"]) {
            event[name] = [[value stringByTrimmingCharactersInSet:ws] uppercaseString];
        }
    }
    return out;
}

static NSArray *cb_ics_items(NSString *text, NSString *canvasHome) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *e in IcsEvents(text)) {
        NSString *summary = e[@"SUMMARY"];
        NSDate *due = e[@"DTSTART"] ?: e[@"DTEND"];
        if (!summary.length || !due) continue;

        NSString *uid = e[@"UID"] ?: @"";
        NSString *url = e[@"URL"] ?: @"";
        if (![uid containsString:@"assignment"] && ![url containsString:@"assignment_"])
            continue;

        NSString *name = nil, *course = nil;
        SplitSummary(summary, &name, &course);
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"name"] = name;
        item[@"due"] = [ISOFormatter() stringFromDate:due];
        if (course) item[@"course"] = course;
        NSString *link = AssignmentURL(url, canvasHome);
        if (link.length) item[@"url"] = link;
        [items addObject:item];
    }

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"due"] compare:b[@"due"]];
    }];
    return items;
}

static NSArray *cb_ics_window(NSArray *items, NSDate *now, int backDays,
                              int aheadDays, NSUInteger cap) {
    NSDate *from = [now dateByAddingTimeInterval:-backDays * 86400.0];
    NSDate *to = [now dateByAddingTimeInterval:aheadDays * 86400.0];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *a in items) {
        NSDate *due = [ISOFormatter() dateFromString:a[@"due"]];
        if (!due) continue;
        if ([due compare:from] == NSOrderedAscending) continue;
        if ([due compare:to] == NSOrderedDescending) continue;
        [out addObject:a];
        if (out.count >= cap) break;
    }
    return out;
}

static BOOL WriteCache(NSArray *items) {
    NSDictionary *root = @{ @"generated": [ISOFormatter() stringFromDate:[NSDate date]],
                            @"items": items ?: @[] };
    NSData *d = [NSJSONSerialization dataWithJSONObject:root
                                                options:NSJSONWritingPrettyPrinted
                                                  error:NULL];
    if (!d) return NO;
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[CachePath() stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    return [d writeToFile:CachePath() atomically:YES];
}

static NSDictionary *LoadCache(void) {
    NSData *d = [NSData dataWithContentsOfFile:CachePath()];
    if (!d) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    return [root isKindOfClass:[NSDictionary class]] ? root : nil;
}

static NSArray *LoadUpcoming(void) {
    id items = LoadCache()[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

static NSString *CacheAgeLabel(void) {
    NSDictionary *c = LoadCache();
    if (!c) return @"no data";
    NSDate *gen = nil;
    id g = c[@"generated"];
    if ([g isKindOfClass:[NSString class]]) gen = [ISOFormatter() dateFromString:g];
    if (!gen) return @"";
    NSTimeInterval age = -[gen timeIntervalSinceNow];
    if (age < 5400) return @"";
    if (age < 86400) return [NSString stringWithFormat:@"%dh ago", (int)(age / 3600)];
    return [NSString stringWithFormat:@"%dd ago", (int)(age / 86400)];
}

static NSDate *ParseISO(NSString *s) {
    static NSISO8601DateFormatter *plain, *fractional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [[NSISO8601DateFormatter alloc] init];
        fractional = [[NSISO8601DateFormatter alloc] init];
        fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime
                                 | NSISO8601DateFormatWithFractionalSeconds;
    });
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSDate *d = [plain dateFromString:s];
    return d ?: [fractional dateFromString:s];
}

static NSString *DueLabel(NSCalendar *cal, NSDate *due) {
    if (!due) return @"";
    NSDate *a, *b;
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&a interval:NULL forDate:[NSDate date]];
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&b interval:NULL forDate:due];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:a toDate:b options:0] day];

    NSDateComponents *tc = [cal components:(NSCalendarUnitHour|NSCalendarUnitMinute)
                                  fromDate:due];
    NSString *clock = HHMMshort((int)tc.hour * 60 + (int)tc.minute);

    if (days < 0)  return @"late";
    if (days == 0) return [NSString stringWithFormat:@"today %@", clock];
    if (days == 1) return [NSString stringWithFormat:@"tmr %@", clock];
    if (days < 7)  return [NSString stringWithFormat:@"%ldd", (long)days];

    static const char *mon[] = {"Jan","Feb","Mar","Apr","May","Jun",
                                "Jul","Aug","Sep","Oct","Nov","Dec"};
    NSDateComponents *c = [cal components:(NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:due];
    return [NSString stringWithFormat:@"%s %ld", mon[c.month - 1], (long)c.day];
}

static NSString *Clip(NSString *s, NSUInteger n) {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length <= n) return s;
    return [[s substringToIndex:n - 1] stringByAppendingString:@"…"];
}

@interface FooterView : NSView
@property (weak) id target;
@property (assign) SEL quitAction;
@property (assign) SEL refreshAction;
@property (assign) BOOL overRefresh;
@property (assign) BOOL hovered;
@property (copy)   NSString *status;
@end

@implementation FooterView

- (NSRect)refreshRect {
    return NSMakeRect(NSMaxX(self.bounds) - 34, NSMidY(self.bounds) - 9, 20, 18);
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
    if (refresh != self.overRefresh || !self.hovered) {
        self.overRefresh = refresh;
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
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    SEL sel;
    if (NSPointInRect(pt, NSInsetRect([self refreshRect], -4, -4))) {
        sel = self.refreshAction;
    } else {
        [self.enclosingMenuItem.menu cancelTracking];
        sel = self.quitAction;
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
    BOOL quitLit = self.hovered && !self.overRefresh;

    if (quitLit) {
        NSRect hl = NSMakeRect(5, 2,
                               NSMinX([self refreshRect]) - 15,
                               NSHeight(self.bounds) - 4);
        NSBezierPath *hp = [NSBezierPath bezierPathWithRoundedRect:hl xRadius:6 yRadius:6];
        [[NSColor selectedContentBackgroundColor] setFill];
        [hp fill];
    }

    NSDictionary *a = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: quitLit ? [NSColor alternateSelectedControlTextColor]
                                                : [NSColor labelColor]
    };
    NSSize qs = [@"Quit" sizeWithAttributes:a];
    [@"Quit" drawAtPoint:NSMakePoint(14, NSMidY(self.bounds) - qs.height / 2)
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
}

@end

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *status;
@property (strong) Schedule *schedule;
@property (assign) NSTimeInterval scheduleStamp;
@property (weak)   FooterView *footer;
@property (weak)   NSMenu *liveMenu;
@property (assign) BOOL fetching;
@property (copy)   NSString *link;
@end

@implementation ClassBar

- (void)applicationDidFinishLaunching:(NSNotification *)note __unused {
    [self reloadScheduleIfChanged];
    self.link = self.schedule.canvasHome;
    self.status = [[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength];

    NSImage *img = CatIconImage();
    self.status.button.image = img;
    self.status.button.imagePosition = NSImageOnly;

    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = self;
    m.autoenablesItems = NO;
    self.status.menu = m;

    [self refreshIfStale];
}

- (void)reloadScheduleIfChanged {
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:SchedulePath() error:NULL];
    NSTimeInterval stamp = [attrs.fileModificationDate timeIntervalSince1970];
    if (self.schedule && stamp == self.scheduleStamp) return;
    self.schedule = [Schedule loadFromDisk];
    self.scheduleStamp = stamp;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [self reloadScheduleIfChanged];

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *p = [cal
        components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|
                    NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitWeekday)
          fromDate:[NSDate date]];

    int ymd  = (int)p.year * 10000 + (int)p.month * 100 + (int)p.day;
    int mins = (int)p.hour * 60 + (int)p.minute;
    int day  = (int)p.weekday - 2;
    if (day < 0) day = 6;

    NSArray *up = LoadUpcoming();

    NSDictionary *rowFont = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };
    CGFloat rowMax = 0;
    for (NSDictionary *a in up) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSString *nm = a[@"name"];
        if (![nm isKindOfClass:[NSString class]]) continue;
        NSString *label = [NSString stringWithFormat:@"%@   %@",
                           DueLabel(cal, ParseISO(a[@"due"])), Clip(nm, 36)];
        CGFloat w = [label sizeWithAttributes:rowFont].width;
        if (w > rowMax) rowMax = w;
    }
    CGFloat cardWidth = MAX(292.0, ceil(rowMax) + 26.0);

    NSArray *series = cb_series(self.schedule, ymd, mins, day, 2);
    {
        NSColor *purple = [NSColor colorWithSRGBRed:0.722 green:0.655 blue:0.945 alpha:1.0];
        NSColor *blue   = [NSColor colorWithSRGBRed:0.651 green:0.839 blue:0.933 alpha:1.0];
        for (NSUInteger k = 0; k < series.count; k++) {
            NSDictionary *e = series[k];
            NSString *t = (k == 0 || [e[@"notice"] boolValue])
                        ? e[@"title"]
                        : [NSString stringWithFormat:@"Next: %@", e[@"title"]];
            [menu addItem:CardItem(t, e[@"code"], e[@"when"], e[@"room"], e[@"link"],
                                   e[@"zoom"], e[@"tip"],
                                   (k == 0 && ![e[@"done"] boolValue]) ? purple : blue,
                                   cardWidth)];
        }
    }

    if (up.count) {
        for (NSDictionary *a in up) {
            if (![a isKindOfClass:[NSDictionary class]]) continue;
            NSString *nm = a[@"name"], *cs = a[@"course"], *ur = a[@"url"];
            if (![nm isKindOfClass:[NSString class]]) continue;
            NSDate *due = ParseISO(a[@"due"]);
            NSString *dl = DueLabel(cal, due);
            BOOL late = [dl isEqualToString:@"late"];

            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:nm
                                                        action:@selector(openItem:)
                                                 keyEquivalent:@""];
            NSString *label = [NSString stringWithFormat:@"%@   %@", dl, Clip(nm, 36)];
            NSMutableAttributedString *at = [[NSMutableAttributedString alloc]
                initWithString:label attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:12]
                }];
            [at addAttributes:@{
                NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11
                                          weight:late ? NSFontWeightBold : NSFontWeightMedium],
                NSForegroundColorAttributeName: late ? [NSColor systemRedColor]
                                                     : [NSColor secondaryLabelColor]
            } range:NSMakeRange(0, dl.length)];
            it.attributedTitle = at;
            it.target = self;
            it.enabled = [ur isKindOfClass:[NSString class]];
            it.representedObject = ur;
            NSString *full = [nm stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *tip = [cs isKindOfClass:[NSString class]]
                ? [NSString stringWithFormat:@"%@\n%@", cs, full] : full;
            if (due) {
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                df.dateFormat = @"EEE MMM d, h:mm a";
                tip = [tip stringByAppendingFormat:@"\nDue %@", [df stringFromDate:due]];
            }
            it.toolTip = tip;
            [menu addItem:it];
        }
    }

    FooterView *fv = [[FooterView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, 26)];
    fv.autoresizingMask = NSViewWidthSizable;
    fv.target = self;
    fv.quitAction = @selector(quitApp);
    fv.refreshAction = @selector(refreshNow);
    fv.status = self.fetching ? @"Syncing…" : CacheAgeLabel();
    self.footer = fv;
    self.liveMenu = menu;
    NSMenuItem *q = [[NSMenuItem alloc] init];
    q.view = fv;
    [menu addItem:q];

    [self refreshIfStale];
}

- (void)head:(NSMenu *)m text:(NSString *)s {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:s action:nil keyEquivalent:@""];
    i.attributedTitle = [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
    }];
    i.enabled = NO;
    [m addItem:i];
}

- (void)sub:(NSMenu *)m text:(NSString *)s {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:s action:nil keyEquivalent:@""];
    i.attributedTitle = [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11
                                                              weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    }];
    i.enabled = NO;
    [m addItem:i];
}

- (void)openCanvas {
    NSURL *u = [NSURL URLWithString:self.link];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (void)openItem:(NSMenuItem *)sender {
    NSString *s = sender.representedObject;
    if (![s isKindOfClass:[NSString class]]) return;
    NSURL *u = [NSURL URLWithString:s];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (NSTimeInterval)cacheStamp {
    NSDictionary *at = [[NSFileManager defaultManager]
        attributesOfItemAtPath:CachePath() error:NULL];
    return [at.fileModificationDate timeIntervalSince1970];
}

- (void)setFooterStatus:(NSString *)text {
    self.footer.status = text;
    self.footer.needsDisplay = YES;
}

- (void)refreshNow {
    if (self.fetching) return;

    NSString *feed = self.schedule.canvasFeed;
    if (!feed.length) {
        self.scheduleStamp = 0;
        [self setFooterStatus:@"No Canvas feed"];
        return;
    }

    NSString *https = [feed hasPrefix:@"webcal://"]
        ? [@"https://" stringByAppendingString:[feed substringFromIndex:9]]
        : feed;
    NSURL *url = [NSURL URLWithString:https];
    if (!url.host) {
        [self setFooterStatus:@"Bad feed URL"];
        return;
    }

    self.fetching = YES;
    [self setFooterStatus:@"Syncing…"];

    NSString *home = self.schedule.canvasHome;
    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:20];
    __weak ClassBar *weak = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]]
                       ? [(NSHTTPURLResponse *)resp statusCode] : 200;
        NSString *body = (data && !err && code < 400)
            ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSArray *items = body ? cb_ics_window(cb_ics_items(body, home),
                                              [NSDate date], 14, 21, 25)
                              : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weak finishFetch:items failure:(code >= 400 ? @"Canvas said no" : nil)];
        });
    }];
    [task resume];
}

- (void)finishFetch:(NSArray *)items failure:(NSString *)failure {
    self.fetching = NO;
    if (!items) {
        [self setFooterStatus:failure ?: @"Fetch failed"];
        return;
    }
    if (!WriteCache(items)) {
        [self setFooterStatus:@"Cache write failed"];
        return;
    }
    NSMenu *m = self.liveMenu;
    if (m.numberOfItems > 0) [self menuNeedsUpdate:m];
    [self setFooterStatus:@"Updated"];
}

- (void)refreshIfStale {
    if (self.fetching || !self.schedule.canvasFeed.length) return;
    NSTimeInterval stamp = [self cacheStamp];
    if (stamp > 0 && [NSDate date].timeIntervalSince1970 - stamp < 1800) return;
    [self refreshNow];
}

- (void)quitApp { [NSApp terminate:nil]; }

@end

#ifdef CLASSBAR_TEST
static int fails = 0;
static Schedule *gSched;

static void T(const char *label, int ymd, int mins, int day,
              const char *wantTitle, const char *wantWhen) {
    NSArray *r = cb_series(gSched, ymd, mins, day, 1);
    NSDictionary *e = r.firstObject;
    NSString *title = e[@"title"], *when = e[@"when"], *room = e[@"room"];
    BOOL okT = [title isEqualToString:@(wantTitle)];
    BOOL okW = (wantWhen == NULL) || [when isEqualToString:@(wantWhen)];
    if (!okT || !okW) {
        fails++;
        printf("  FAIL %-32s got [%s | %s]  want [%s | %s]\n", label,
               title.UTF8String, when.UTF8String, wantTitle, wantWhen ? wantWhen : "*");
    } else {
        printf("  ok   %-32s %s · %s%s%s\n", label, title.UTF8String, when.UTF8String,
               room.length ? " · " : "", room.UTF8String);
    }
}

static void T2(const char *label, int ymd, int mins, int day,
               const char *want1, const char *want2) {
    NSArray *r = cb_series(gSched, ymd, mins, day, 2);
    NSString *a = r.count > 0 ? r[0][@"title"] : @"";
    NSString *b = r.count > 1 ? r[1][@"title"] : @"";
    BOOL ok = [a isEqualToString:@(want1)] && [b isEqualToString:@(want2)];
    if (!ok) {
        fails++;
        printf("  FAIL %-32s got [%s, %s]  want [%s, %s]\n", label,
               a.UTF8String, b.UTF8String, want1, want2);
    } else {
        printf("  ok   %-32s %s -> %s\n", label, a.UTF8String, b.UTF8String);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gSched = [Schedule loadFromDisk];

        if (argc > 1) {
            NSString *text = [NSString stringWithContentsOfFile:@(argv[1])
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
            if (!text) { printf("cannot read %s\n", argv[1]); return 1; }
            NSArray *all = cb_ics_items(text, gSched.canvasHome);
            NSArray *kept = cb_ics_window(all, [NSDate date], 14, 21, 25);
            printf("%s\n  %lu assignments, %lu in window\n", argv[1],
                   (unsigned long)all.count, (unsigned long)kept.count);
            NSCalendar *c = [NSCalendar currentCalendar];
            for (NSDictionary *a in kept)
                printf("  %-7s %-38s %s\n",
                       DueLabel(c, ParseISO(a[@"due"])).UTF8String,
                       Clip(a[@"name"], 36).UTF8String,
                       [a[@"course"] ?: @"" UTF8String]);
            if (kept.count) printf("  url: %s\n", [kept[0][@"url"] UTF8String]);
            return 0;
        }

        printf("schedule: %s\n", gSched.loadError ? gSched.loadError.UTF8String : "loaded");
        for (int d = 0; d < 7; d++) {
            NSArray *l = gSched.byDay[d];
            if (!l.count) continue;
            printf("  %-9s ", kDayName[d]);
            for (NSDictionary *c in l)
                printf("%s(%s) ", [c[@"name"] UTF8String],
                       HHMMshort([c[@"start"] intValue]).UTF8String);
            printf("\n");
        }

        printf("\ncb_series — first entry\n");
        T("before term",             20260907, 600,  0, "Term hasn't started", NULL);
        T("Mon 9:00 (15m before)",    20260914, 540,  0, "Gen Chem",        "9:15a • in 15m");
        T("Mon 9:15 (start edge)",    20260914, 555,  0, "Gen Chem",        "9:15a • 1h 5m left");
        T("Mon 10:19 (last minute)",  20260914, 619,  0, "Gen Chem",        "9:15a • 1m left");
        T("Mon 10:20 (end edge)",     20260914, 620,  0, "CHEM Recitation", "11:45a • in 1h 25m");
        T("Mon 4:30 (CRWT ended)",    20260914, 990,  0, "Cornerstone 1",   "4:35p • in 5m");
        T("Mon 4:35 (Cornerstone)",   20260914, 995,  0, "Cornerstone 1",   "4:35p • 1h 5m left");
        T("Mon 6:00 PM (day over)",   20260914, 1080, 0, "done for the day! :3", "");
        T("Tue -> Wed",               20260915, 700,  1, "Gen Chem",        "Wed 9:15a");
        T("Thu 6:00 PM (day over)",   20260917, 1080, 3, "done for the day! :3", "");
        T("Fri -> Mon",               20260918, 700,  4, "Gen Chem",        "Mon 9:15a");
        T("Sun -> Mon",               20260920, 700,  6, "Gen Chem",        "Mon 9:15a");
        T("Thu 10:30 -> Calculus",    20260917, 630,  3, "Calculus 2",      "1:35p • in 3h 5m");
        T("after term",               20261221, 600,  0, "Term is over",    "");

        printf("\ncb_series — current + next pairing\n");
        T2("Mon 9:30 in Gen Chem",    20260914, 570,  0, "Gen Chem", "CHEM Recitation");
        T2("Mon 4:00 in CRWT",        20260914, 960,  0, "Creative Writing", "Cornerstone 1");
        T2("Thu evening is done",     20260917, 1080, 3, "done for the day! :3", "");
        T2("Tue (free) -> Wed pair",  20260915, 700,  1, "Gen Chem", "Calculus 2");
        T2("Mon 5:00 last class",     20260914, 1020, 0, "Cornerstone 1", "done for the day! :3");
        T2("Mon 4:30 before last",    20260914, 990,  0, "Cornerstone 1", "done for the day! :3");
        T2("Thu 5:00 last class",     20260917, 1020, 3, "Cornerstone 1", "done for the day! :3");

        printf("\ndone-for-the-day tip\n");
        NSString *tip = cb_series(gSched, 20260914, 1080, 0, 1)[0][@"tip"];
        BOOL tipOK = [tip hasPrefix:@"Next: Gen Chem"] &&
                     [tip containsString:@"Wed 9:15a"];
        printf("  %-4s done card names the next class\n", tipOK ? "ok" : "FAIL");
        if (!tipOK) { fails++; printf("       got [%s]\n", tip.UTF8String); }

        printf("\nzoom + canvas links\n");
        NSArray *crwt = cb_series(gSched, 20260914, 960, 0, 1);
        BOOL hasZoom = [crwt[0][@"zoom"] length] > 0;
        printf("  %-4s CRWT card carries a zoom link\n", hasZoom ? "ok" : "FAIL");
        if (!hasZoom) fails++;
        NSArray *chem = cb_series(gSched, 20260914, 540, 0, 1);
        BOOL chemLink = [chem[0][@"link"] hasSuffix:@"259102"];
        printf("  %-4s Gen Chem links to its canvas course\n", chemLink ? "ok" : "FAIL");
        if (!chemLink) fails++;

        printf("\ndue date parsing\n");
        const char *stamps[] = {
            "2026-09-11T16:00:00Z",
            "2026-09-11T12:00:00.000-04:00",
            "2026-09-11T12:00:00-04:00",
            "2026-09-11T16:00:00.123Z",
        };
        for (size_t i = 0; i < sizeof(stamps) / sizeof(stamps[0]); i++) {
            NSDate *d = ParseISO(@(stamps[i]));
            if (!d) fails++;
            printf("  %-4s %s\n", d ? "ok" : "FAIL", stamps[i]);
        }

        printf("\ncanvas ics parsing\n");
        NSString *ics = [@[
            @"BEGIN:VCALENDAR",
            @"VERSION:2.0",
            @"BEGIN:VEVENT",
            @"UID:event-assignment-3409619@example.instructure.com",
            @"DTSTART;VALUE=DATE-TIME:20260911T160000Z",
            @"SUMMARY:Week 2 - Upload Poems to be",
            @"  Workshopped [CRWT 1170 Intro to Poetry]",
            [@"URL:https://example.instructure.com/calendar?include_contexts=course_260574"
              stringByAppendingString:@"&month=09-11-2026#assignment_3409619"],
            @"END:VEVENT",
            @"BEGIN:VEVENT",
            @"UID:event-calendar-event-999@example.instructure.com",
            @"DTSTART;TZID=America/New_York:20260910T090000",
            @"SUMMARY:Office Hours [CRWT 1170]",
            @"END:VEVENT",
            @"BEGIN:VEVENT",
            @"UID:event-assignment-1@example.instructure.com",
            @"DTSTART;VALUE=DATE:20260909",
            @"SUMMARY:Reading response\\, part one [ENGW 1111]",
            @"END:VEVENT",
            @"END:VCALENDAR",
        ] componentsJoinedByString:@"\r\n"];

        NSArray *parsed = cb_ics_items(ics, @"https://example.instructure.com/");
        struct { const char *label; BOOL ok; } icsChecks[] = {
            { "calendar events are skipped",  parsed.count == 2 },
            { "sorted by due date",           parsed.count == 2 &&
                  [parsed[0][@"name"] hasPrefix:@"Reading response"] },
            { "folded summary is rejoined",   parsed.count == 2 &&
                  [parsed[1][@"name"] isEqualToString:
                      @"Week 2 - Upload Poems to be Workshopped"] },
            { "course is split off",          parsed.count == 2 &&
                  [parsed[1][@"course"] isEqualToString:@"CRWT 1170 Intro to Poetry"] },
            { "escapes are decoded",          parsed.count == 2 &&
                  [parsed[0][@"name"] isEqualToString:@"Reading response, part one"] },
            { "direct assignment url",        parsed.count == 2 &&
                  [parsed[1][@"url"] isEqualToString:
                      @"https://example.instructure.com/courses/260574/assignments/3409619"] },
            { "utc due time converted",       parsed.count == 2 &&
                  [ISOFormatter() dateFromString:parsed[1][@"due"]] != nil },
        };
        for (size_t i = 0; i < sizeof(icsChecks) / sizeof(icsChecks[0]); i++) {
            if (!icsChecks[i].ok) fails++;
            printf("  %-4s %s\n", icsChecks[i].ok ? "ok" : "FAIL", icsChecks[i].label);
        }

        NSDate *anchor = [ISOFormatter() dateFromString:@"2026-09-11T00:00:00Z"];
        BOOL windowOK = cb_ics_window(parsed, anchor, 14, 21, 25).count == 2 &&
                        cb_ics_window(parsed, anchor, 0, 21, 25).count == 1 &&
                        cb_ics_window(parsed, anchor, 14, 21, 1).count == 1;
        if (!windowOK) fails++;
        printf("  %-4s window trims by age, horizon, and cap\n", windowOK ? "ok" : "FAIL");

        printf("\nassignment cache\n");
        NSArray *up = LoadUpcoming();
        if (!up.count) printf("  (none at %s)\n", CachePath().UTF8String);
        NSCalendar *cal = [NSCalendar currentCalendar];
        for (NSDictionary *a in up) {
            NSDate *due = ParseISO(a[@"due"]);
            printf("  %-7s %s\n", DueLabel(cal, due).UTF8String, Clip(a[@"name"], 34).UTF8String);
        }

        printf("\n%s (%d failures)\n", fails ? "FAILED" : "ALL PASS", fails);
    }
    return fails ? 1 : 0;
}
#else
int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        static ClassBar *delegate;
        delegate = [[ClassBar alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
#endif
