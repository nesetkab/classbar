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
@property (copy)   NSString *refreshAgent;
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
    if ([root[@"refreshAgent"] isKindOfClass:[NSString class]]) s.refreshAgent = root[@"refreshAgent"];
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

@interface CardView : NSView
@property (copy) NSString *title;
@property (copy) NSString *code;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (copy) NSString *link;
@property (copy) NSString *zoom;
@property (strong) NSColor *bg;
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

- (void)syncHoverAt:(NSPoint)pt {
    BOOL onPill = self.zoom.length && NSPointInRect(pt, [self pillRect]);
    if (onPill != self.overPill || !self.hovered) {
        self.overPill = onPill;
        self.hovered = YES;
        self.needsDisplay = YES;
    }
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
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) { self.hovered = NO; self.overPill = NO; }
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    NSString *target = (self.zoom.length && NSPointInRect(pt, [self pillRect]))
                     ? self.zoom : self.link;
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
                            NSString *link, NSString *zoom, NSColor *bg, CGFloat width) {
    CardView *v = [[CardView alloc] initWithFrame:NSMakeRect(0, 0, width, 52)];
    v.autoresizingMask = NSViewWidthSizable;
    v.title = title; v.code = code; v.when = when; v.room = room;
    v.link = link; v.zoom = zoom; v.bg = bg;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
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
    if ([g isKindOfClass:[NSString class]]) {
        static NSISO8601DateFormatter *f;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
        gen = [f dateFromString:g];
    }
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
    BOOL on = NSPointInRect(pt, NSInsetRect([self refreshRect], -6, -4));
    if (on != self.overRefresh || !self.hovered) {
        self.overRefresh = on; self.hovered = YES; self.needsDisplay = YES;
    }
}

- (void)mouseMoved:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e {
    self.hovered = NO; self.overRefresh = NO; self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    BOOL refresh = NSPointInRect(pt, NSInsetRect([self refreshRect], -6, -4));
    if (!refresh) [self.enclosingMenuItem.menu cancelTracking];
    SEL sel = refresh ? self.refreshAction : self.quitAction;
    if (self.target && sel) ((void (*)(id, SEL))objc_msgSend)(self.target, sel);
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

    NSRect r = [self refreshRect];
    if (self.overRefresh) {
        NSBezierPath *bgp = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -4, -2)
                                                            xRadius:5 yRadius:5];
        [[NSColor selectedContentBackgroundColor] setFill];
        [bgp fill];
    }

    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
        isEqualToString:NSAppearanceNameDarkAqua];
    NSImage *ri = RefreshIconImage(dark || self.overRefresh);
    if (ri) {
        NSSize sz = ri.size;
        [ri drawInRect:NSMakeRect(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2,
                                  sz.width, sz.height)
              fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }
}

@end

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *status;
@property (strong) Schedule *schedule;
@property (assign) NSTimeInterval scheduleStamp;
@property (weak)   FooterView *footer;
@property (weak)   NSMenu *liveMenu;
@property (strong) NSTimer *syncPoll;
@property (assign) NSTimeInterval syncStartedAt;
@property (assign) NSTimeInterval cacheStampAtSync;
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
            NSString *t = k == 0 ? e[@"title"]
                        : [NSString stringWithFormat:@"Next: %@", e[@"title"]];
            [menu addItem:CardItem(t, e[@"code"], e[@"when"], e[@"room"], e[@"link"],
                                   e[@"zoom"], k == 0 ? purple : blue, cardWidth)];
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
    fv.status = self.syncPoll ? @"Syncing…" : CacheAgeLabel();
    self.footer = fv;
    self.liveMenu = menu;
    NSMenuItem *q = [[NSMenuItem alloc] init];
    q.view = fv;
    [menu addItem:q];
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
    if (self.syncPoll) return;

    NSString *label = self.schedule.refreshAgent;
    if (!label.length) {
        self.scheduleStamp = 0;
        [self setFooterStatus:@"No sync agent"];
        return;
    }

    self.cacheStampAtSync = [self cacheStamp];
    self.syncStartedAt = [NSDate timeIntervalSinceReferenceDate];
    [self setFooterStatus:@"Syncing…"];

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    t.arguments = @[@"kickstart", @"-k",
                    [NSString stringWithFormat:@"gui/%u/%@", getuid(), label]];
    if (![t launchAndReturnError:NULL]) {
        [self setFooterStatus:@"Sync failed"];
        return;
    }

    self.syncPoll = [NSTimer timerWithTimeInterval:0.5
                                            target:self
                                          selector:@selector(pollSync)
                                          userInfo:nil
                                           repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.syncPoll forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:self.syncPoll forMode:NSDefaultRunLoopMode];
}

- (void)stopPolling {
    [self.syncPoll invalidate];
    self.syncPoll = nil;
}

- (void)pollSync {
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - self.syncStartedAt;

    if ([self cacheStamp] > self.cacheStampAtSync) {
        [self stopPolling];
        [self setFooterStatus:@"Updated"];
        NSMenu *m = self.liveMenu;
        if (m.numberOfItems > 0) [self menuNeedsUpdate:m];
        [self setFooterStatus:@"Updated"];
        return;
    }
    if (elapsed > 120) {
        [self stopPolling];
        [self setFooterStatus:@"Sync timed out"];
    }
}

- (void)menuDidClose:(NSMenu *)menu { [self stopPolling]; }

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

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gSched = [Schedule loadFromDisk];

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
        T("Mon 6:00 PM -> Wed",       20260914, 1080, 0, "Gen Chem",        "Wed 9:15a");
        T("Tue -> Wed",               20260915, 700,  1, "Gen Chem",        "Wed 9:15a");
        T("Thu 6:00 PM -> Mon",       20260917, 1080, 3, "Gen Chem",        "Mon 9:15a");
        T("Fri -> Mon",               20260918, 700,  4, "Gen Chem",        "Mon 9:15a");
        T("Sun -> Mon",               20260920, 700,  6, "Gen Chem",        "Mon 9:15a");
        T("Thu 10:30 -> Calculus",    20260917, 630,  3, "Calculus 2",      "1:35p • in 3h 5m");
        T("after term",               20261221, 600,  0, "Term is over",    "");

        printf("\ncb_series — current + next pairing\n");
        T2("Mon 9:30 in Gen Chem",    20260914, 570,  0, "Gen Chem", "CHEM Recitation");
        T2("Mon 4:00 in CRWT",        20260914, 960,  0, "Creative Writing", "Cornerstone 1");
        T2("Thu evening rolls to Mon",20260917, 1080, 3, "Gen Chem", "CHEM Recitation");
        T2("Tue (free) -> Wed pair",  20260915, 700,  1, "Gen Chem", "Calculus 2");

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
