#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "app.h"
#import "views.h"
#import "settings.h"
#import "ics.h"
#import "schedule.h"
#import "store.h"
#import "icons.h"

@interface ClassBar ()
@property (strong) NSStatusItem *status;
@property (assign) NSTimeInterval scheduleStamp;
@property (weak)   FooterView *footer;
@property (weak)   NSMenu *liveMenu;
@property (assign) BOOL fetching;
@property (assign) BOOL menuOpen;
@property (strong) NSArray *cachedItems;
@property (strong) SettingsWindow *settings;
@property (copy)   NSString *link;
@end

static const NSTimeInterval kRefreshFloorSeconds = 10;
static const NSTimeInterval kStaleSeconds = 300;

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

    [self refreshIfOlderThan:kRefreshFloorSeconds];
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

    NSDate *now = [NSDate date];
    self.cachedItems = LoadUpcoming();
    NSMutableArray *pending = [NSMutableArray array];
    for (NSDictionary *a in self.cachedItems) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSDate *due = ParseISO(a[@"due"]);
        if (due && [due compare:now] == NSOrderedAscending) continue;
        [pending addObject:a];
    }
    NSArray *up = pending;
    if ((int)up.count > self.schedule.assignmentCap)
        up = [up subarrayWithRange:NSMakeRange(0, (NSUInteger)self.schedule.assignmentCap)];

    NSDictionary *rowFont = @{ NSFontAttributeName: NameFont() };
    CGFloat nameMax = 0, dueMax = 0;
    for (NSDictionary *a in up) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSString *nm = a[@"name"];
        if (![nm isKindOfClass:[NSString class]]) continue;
        NSString *dl = DueLabel(cal, ParseISO(a[@"due"]));
        NSFont *dueFont = DueFont([dl isEqualToString:@"late"]);
        CGFloat dw = [dl sizeWithAttributes:@{ NSFontAttributeName: dueFont }].width;
        if (dw > dueMax) dueMax = dw;
        CGFloat nw = [Clip(nm, 36) sizeWithAttributes:rowFont].width;
        if (nw > nameMax) nameMax = nw;
    }
    CGFloat dueWidth = ceil(dueMax);
    CGFloat cardWidth = MAX(292.0, dueWidth + kDueColumnGap + ceil(nameMax) + 26.0);

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

            NSString *full = [nm stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *whenLine = @"";
            if (due) {
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                df.dateFormat = @"EEE MMM d · h:mm a";
                whenLine = [NSString stringWithFormat:@"Due %@", [df stringFromDate:due]];
            }
            NSString *tip = TipText(full,
                @[[cs isKindOfClass:[NSString class]] ? cs : @"", whenLine]);

            [menu addItem:AssignmentItem(dl, Clip(nm, 36),
                                         [ur isKindOfClass:[NSString class]] ? ur : @"",
                                         tip, late, dueWidth, cardWidth)];
        }
    }

    FooterView *fv = [[FooterView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, 26)];
    fv.autoresizingMask = NSViewWidthSizable;
    fv.target = self;
    fv.quitAction = @selector(quitApp);
    fv.refreshAction = @selector(refreshNow);
    fv.settingsAction = @selector(openSettings);
    fv.status = self.fetching ? @"Syncing…" : CacheAgeLabel();
    self.footer = fv;
    self.liveMenu = menu;
    NSMenuItem *q = [[NSMenuItem alloc] init];
    q.view = fv;
    [menu addItem:q];

    [self refreshIfOlderThan:kStaleSeconds];
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

- (NSTimeInterval)cacheStamp {
    NSDictionary *at = [[NSFileManager defaultManager]
        attributesOfItemAtPath:CachePath() error:NULL];
    return [at.fileModificationDate timeIntervalSince1970];
}

- (void)setFooterStatus:(NSString *)text {
    self.footer.status = text;
    self.footer.needsDisplay = YES;
    [self.settings setStatus:text];
}

- (void)openSettings {
    if (!self.settings) {
        self.settings = [[SettingsWindow alloc] init];
        self.settings.target = self;
        self.settings.savedAction = @selector(settingsSaved);
        self.settings.refreshAction = @selector(refreshNow);
    }
    [self.settings show];
}

- (void)settingsSaved {
    self.scheduleStamp = 0;
    [self reloadScheduleIfChanged];
    self.link = self.schedule.canvasHome;
    [self refreshNow];
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
                                              [NSDate date], 0, 21,
                                              kCacheAssignmentCap)
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
    BOOL changed = !self.cachedItems || ![items isEqualToArray:self.cachedItems];
    NSMenu *m = self.liveMenu;
    if (changed && self.menuOpen && m) [self menuNeedsUpdate:m];
    [self setFooterStatus:@"Updated"];
}

- (void)refreshIfOlderThan:(NSTimeInterval)age {
    if (self.fetching || !self.schedule.canvasFeed.length) return;
    NSTimeInterval stamp = [self cacheStamp];
    if (stamp > 0 && [NSDate date].timeIntervalSince1970 - stamp < age) return;
    [self refreshNow];
}

- (void)menuWillOpen:(NSMenu *)menu __unused {
    self.menuOpen = YES;
}

- (void)menuDidClose:(NSMenu *)menu __unused {
    self.menuOpen = NO;
    TipHide();
    [self refreshIfOlderThan:kRefreshFloorSeconds];
}

- (void)quitApp { [NSApp terminate:nil]; }

@end
