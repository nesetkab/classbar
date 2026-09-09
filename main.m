#import <Cocoa/Cocoa.h>

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
            @"room": [c[@"room"] isKindOfClass:[NSString class]] ? c[@"room"] : @"",
            @"start": @(st),
            @"end": @(en),
            @"canvas": [c[@"canvas"] isKindOfClass:[NSString class]] ? c[@"canvas"] : @""
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

static NSString *HHMM(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d %s", h, mm, h24 >= 12 ? "PM" : "AM"];
}

static NSString *DUR(int m) {
    if (m < 60) return [NSString stringWithFormat:@"%dm", m];
    int h = m / 60, r = m % 60;
    return r ? [NSString stringWithFormat:@"%dh %dm", h, r]
             : [NSString stringWithFormat:@"%dh", h];
}

static const char * const kDayName[7] = {
    "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"
};

static void cb_resolve(Schedule *s, int ymd, int mins, int day,
                       NSString * __strong *outTitle,
                       NSString * __strong *outWhen,
                       NSString * __strong *outRoom,
                       NSString * __strong *outLink) {
    *outTitle = nil; *outWhen = @""; *outRoom = nil; *outLink = s.canvasHome;

    if (s.loadError) {
        *outTitle = s.loadError;
        *outWhen = @"Add one to Application Support/classbar";
        return;
    }
    if (ymd < s.termStart) { *outTitle = @"Term hasn't started"; *outWhen = s.beforeLabel; return; }
    if (ymd > s.termEnd)   { *outTitle = @"Term is over"; return; }

    NSArray *list = s.byDay[day];
    NSDictionary *hit = nil;
    BOOL inClass = NO;

    for (NSDictionary *c in list) {
        int st = [c[@"start"] intValue], en = [c[@"end"] intValue];
        if (mins >= st && mins < en) { hit = c; inClass = YES; break; }
    }
    if (!hit)
        for (NSDictionary *c in list)
            if ([c[@"start"] intValue] > mins) { hit = c; break; }

    if (hit) {
        int st = [hit[@"start"] intValue], en = [hit[@"end"] intValue];
        *outTitle = hit[@"name"];
        *outRoom  = [hit[@"room"] length] ? hit[@"room"] : nil;
        *outWhen  = inClass
            ? [NSString stringWithFormat:@"ends %@ · %@ left", HHMM(en), DUR(en - mins)]
            : [NSString stringWithFormat:@"%@ · in %@", HHMM(st), DUR(st - mins)];
        if ([hit[@"canvas"] length]) *outLink = hit[@"canvas"];
        return;
    }

    for (int k = 1; k <= 7; k++) {
        int d = (day + k) % 7;
        NSArray *nx = s.byDay[d];
        if (nx.count) {
            NSDictionary *f = nx[0];
            *outTitle = f[@"name"];
            *outRoom  = [f[@"room"] length] ? f[@"room"] : nil;
            *outWhen  = [NSString stringWithFormat:@"%s · %@",
                         kDayName[d], HHMM([f[@"start"] intValue])];
            if ([f[@"canvas"] length]) *outLink = f[@"canvas"];
            return;
        }
    }
    *outTitle = @"No classes";
}

static NSString *HHMMshort(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d%s", h, mm, h24 >= 12 ? "p" : "a"];
}

static NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count) {
    NSMutableArray *out = [NSMutableArray array];
    if (s.loadError || ymd < s.termStart || ymd > s.termEnd) return out;

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
                @"when": when,
                @"room": [hit[@"room"] length] ? hit[@"room"] : @"",
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
    return out;
}

@interface CardView : NSView
@property (copy) NSString *title;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (strong) NSColor *bg;
@end

@implementation CardView

- (void)drawRect:(NSRect)dirty {
    NSRect box = NSInsetRect(self.bounds, 7, 3);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:box xRadius:7 yRadius:7];
    [self.bg setFill];
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

    [self.title drawAtPoint:NSMakePoint(NSMinX(box) + 9, topY) withAttributes:tAttr];
    [self.when drawAtPoint:NSMakePoint(NSMinX(box) + 9, botY) withAttributes:sAttr];

    NSSize rs = [self.room sizeWithAttributes:sAttr];
    [self.room drawAtPoint:NSMakePoint(NSMaxX(box) - 9 - rs.width, botY) withAttributes:sAttr];
}

@end

static NSMenuItem *CardItem(NSString *title, NSString *when, NSString *room, NSColor *bg) {
    CardView *v = [[CardView alloc] initWithFrame:NSMakeRect(0, 0, 292, 52)];
    v.title = title; v.when = when; v.room = room; v.bg = bg;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

static NSArray *LoadUpcoming(void) {
    NSData *d = [NSData dataWithContentsOfFile:CachePath()];
    if (!d) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id items = root[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

static NSDate *ParseISO(NSString *s) {
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
    return [s isKindOfClass:[NSString class]] ? [f dateFromString:s] : nil;
}

static NSString *DueLabel(NSCalendar *cal, NSDate *due) {
    if (!due) return @"";
    NSDate *a, *b;
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&a interval:NULL forDate:[NSDate date]];
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&b interval:NULL forDate:due];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:a toDate:b options:0] day];

    if (days < 0)  return @"late";
    if (days == 0) return @"today";
    if (days == 1) return @"tmrw";
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

static NSImage *CatIcon(void) {
    return [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO
                   drawingHandler:^BOOL(NSRect rect __unused) {
        [[NSColor blackColor] setStroke];
        [[NSColor blackColor] setFill];

        NSBezierPath *p = [NSBezierPath bezierPath];
        p.lineWidth = 1.55;
        p.lineCapStyle = NSLineCapStyleRound;
        p.lineJoinStyle = NSLineJoinStyleRound;
        [p moveToPoint:NSMakePoint(4.6, 11.6)];
        [p lineToPoint:NSMakePoint(3.1, 16.4)];
        [p lineToPoint:NSMakePoint(7.9, 13.6)];
        [p curveToPoint:NSMakePoint(2.5, 8.0)
          controlPoint1:NSMakePoint(4.9, 12.9) controlPoint2:NSMakePoint(2.6, 10.6)];
        [p curveToPoint:NSMakePoint(9.1, 2.6)
          controlPoint1:NSMakePoint(2.4, 4.7) controlPoint2:NSMakePoint(5.5, 2.5)];
        [p curveToPoint:NSMakePoint(15.5, 8.0)
          controlPoint1:NSMakePoint(12.6, 2.7) controlPoint2:NSMakePoint(15.6, 4.8)];
        [p curveToPoint:NSMakePoint(10.2, 13.6)
          controlPoint1:NSMakePoint(15.4, 10.7) controlPoint2:NSMakePoint(13.2, 12.8)];
        [p lineToPoint:NSMakePoint(14.9, 16.2)];
        [p lineToPoint:NSMakePoint(13.5, 11.5)];
        [p stroke];

        NSBezierPath *w = [NSBezierPath bezierPath];
        w.lineWidth = 1.2;
        w.lineCapStyle = NSLineCapStyleRound;
        [w moveToPoint:NSMakePoint(5.4, 7.5)];  [w lineToPoint:NSMakePoint(1.2, 6.7)];
        [w moveToPoint:NSMakePoint(5.4, 6.2)];  [w lineToPoint:NSMakePoint(1.5, 4.8)];
        [w moveToPoint:NSMakePoint(12.6, 7.5)]; [w lineToPoint:NSMakePoint(16.8, 6.7)];
        [w moveToPoint:NSMakePoint(12.6, 6.2)]; [w lineToPoint:NSMakePoint(16.5, 4.8)];
        [w stroke];

        NSBezierPath *e = [NSBezierPath bezierPath];
        [e appendBezierPathWithOvalInRect:NSMakeRect(5.9, 8.3, 2.1, 2.1)];
        [e appendBezierPathWithOvalInRect:NSMakeRect(10.2, 8.3, 2.1, 2.1)];
        [e fill];

        NSBezierPath *n = [NSBezierPath bezierPath];
        n.lineWidth = 1.25;
        n.lineCapStyle = NSLineCapStyleRound;
        n.lineJoinStyle = NSLineJoinStyleRound;
        [n moveToPoint:NSMakePoint(8.2, 6.9)];
        [n lineToPoint:NSMakePoint(9.1, 6.1)];
        [n lineToPoint:NSMakePoint(10.0, 6.9)];
        [n stroke];
        return YES;
    }];
}

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *status;
@property (strong) Schedule *schedule;
@property (assign) NSTimeInterval scheduleStamp;
@property (copy)   NSString *link;
@end

@implementation ClassBar

- (void)applicationDidFinishLaunching:(NSNotification *)note __unused {
    [self reloadScheduleIfChanged];
    self.link = self.schedule.canvasHome;
    self.status = [[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength];

    NSImage *img = CatIcon();
    img.template = YES;
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

    NSArray *series = cb_series(self.schedule, ymd, mins, day, 2);
    if (series.count) {
        NSColor *purple = [NSColor colorWithSRGBRed:0.722 green:0.655 blue:0.945 alpha:1.0];
        NSColor *blue   = [NSColor colorWithSRGBRed:0.651 green:0.839 blue:0.933 alpha:1.0];
        for (NSUInteger k = 0; k < series.count; k++) {
            NSDictionary *e = series[k];
            NSString *t = k == 0 ? e[@"title"]
                        : [NSString stringWithFormat:@"Next: %@", e[@"title"]];
            [menu addItem:CardItem(t, e[@"when"], e[@"room"], k == 0 ? purple : blue)];
        }
    } else {
        NSString *title = nil, *when = nil, *room = nil, *link = nil;
        cb_resolve(self.schedule, ymd, mins, day, &title, &when, &room, &link);
        [self head:menu text:title];
        if (when.length) [self sub:menu text:when];
    }

    NSArray *up = LoadUpcoming();
    if (up.count) {
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSDictionary *a in up) {
            if (![a isKindOfClass:[NSDictionary class]]) continue;
            NSString *nm = a[@"name"], *cs = a[@"course"], *ur = a[@"url"];
            if (![nm isKindOfClass:[NSString class]]) continue;
            NSDate *due = ParseISO(a[@"due"]);
            NSString *dl = DueLabel(cal, due);

            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:nm
                                                        action:@selector(openItem:)
                                                 keyEquivalent:@""];
            NSString *label = [NSString stringWithFormat:@"%@   %@", dl, Clip(nm, 32)];
            NSMutableAttributedString *at = [[NSMutableAttributedString alloc]
                initWithString:label attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:12]
                }];
            [at addAttributes:@{
                NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11
                                                                      weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
            } range:NSMakeRange(0, dl.length)];
            it.attributedTitle = at;
            it.target = self;
            it.enabled = [ur isKindOfClass:[NSString class]];
            it.representedObject = ur;
            it.toolTip = [cs isKindOfClass:[NSString class]] ? cs : nil;
            [menu addItem:it];
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *q = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                               action:@selector(quitApp)
                                        keyEquivalent:@"q"];
    q.target = self; q.enabled = YES;
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

- (void)quitApp { [NSApp terminate:nil]; }

@end

#ifdef CLASSBAR_TEST
static int fails = 0;
static Schedule *gSched;

static void T(const char *label, int ymd, int mins, int day,
              const char *wantTitle, const char *wantWhen) {
    NSString *title = nil, *when = nil, *room = nil, *link = nil;
    cb_resolve(gSched, ymd, mins, day, &title, &when, &room, &link);
    BOOL okT = [title isEqualToString:@(wantTitle)];
    BOOL okW = (wantWhen == NULL) || [when isEqualToString:@(wantWhen)];
    if (!okT || !okW) {
        fails++;
        printf("  FAIL %-34s got [%s | %s]  want [%s | %s]\n", label,
               title.UTF8String, when.UTF8String, wantTitle, wantWhen ? wantWhen : "*");
    } else {
        printf("  ok   %-34s %s · %s%s%s\n", label, title.UTF8String, when.UTF8String,
               room ? " · " : "", room ? room.UTF8String : "");
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gSched = [Schedule loadFromDisk];

        printf("schedule: %s (%s)\n", SchedulePath().UTF8String,
               gSched.loadError ? gSched.loadError.UTF8String : "loaded");
        for (int d = 0; d < 7; d++) {
            NSArray *l = gSched.byDay[d];
            if (!l.count) continue;
            printf("  %-9s ", kDayName[d]);
            for (NSDictionary *c in l)
                printf("%s(%s) ", [c[@"name"] UTF8String],
                       HHMM([c[@"start"] intValue]).UTF8String);
            printf("\n");
        }

        printf("\ncb_resolve cases\n");
        T("before term",              20260907, 600,  0, "Term hasn't started", NULL);
        T("Mon 9:00 (15m before)",     20260914, 540,  0, "Gen Chem",        "9:15 AM · in 15m");
        T("Mon 9:15 (start edge)",     20260914, 555,  0, "Gen Chem",        "ends 10:20 AM · 1h 5m left");
        T("Mon 10:19 (last minute)",   20260914, 619,  0, "Gen Chem",        "ends 10:20 AM · 1m left");
        T("Mon 10:20 (end edge)",      20260914, 620,  0, "CHEM Recitation", "11:45 AM · in 1h 25m");
        T("Mon 4:30 (CRWT just ended)",20260914, 990,  0, "Cornerstone 1",   "4:35 PM · in 5m");
        T("Mon 4:35 (Cornerstone)",    20260914, 995,  0, "Cornerstone 1",   "ends 5:40 PM · 1h 5m left");
        T("Mon 6:00 PM -> Wed",        20260914, 1080, 0, "Gen Chem",        "Wednesday · 9:15 AM");
        T("Tue anytime -> Wed",        20260915, 700,  1, "Gen Chem",        "Wednesday · 9:15 AM");
        T("Thu 6:00 PM -> Mon",        20260917, 1080, 3, "Gen Chem",        "Monday · 9:15 AM");
        T("Fri -> Mon",                20260918, 700,  4, "Gen Chem",        "Monday · 9:15 AM");
        T("Sun -> Mon",                20260920, 700,  6, "Gen Chem",        "Monday · 9:15 AM");
        T("Thu 10:30 -> Calculus",     20260917, 630,  3, "Calculus 2",      "1:35 PM · in 3h 5m");
        T("after term",                20261221, 600,  0, "Term is over",    "");

        printf("\nassignment cache\n");
        NSArray *up = LoadUpcoming();
        if (!up.count) printf("  (none at %s)\n", CachePath().UTF8String);
        for (NSDictionary *a in up) {
            NSDate *due = ParseISO(a[@"due"]);
            printf("  %-6s %s\n", DueLabel([NSCalendar currentCalendar], due).UTF8String, Clip(a[@"name"], 32).UTF8String);
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
