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
@property (strong) NSMutableSet *sessionMarks;
@property (strong) SettingsWindow *settings;
@property (assign) BOOL composing;
@property (assign) BOOL pickingDay;
@property (copy)   NSString *draftName;
@property (strong) NSDate *draftDue;
@property (assign) CGFloat menuWidth;
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
    [self keepDraftFrom:menu];
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
    NSMutableArray *feedAndTasks = [self.cachedItems mutableCopy];
    [feedAndTasks addObjectsFromArray:LoadTasks()];
    [feedAndTasks sortUsingComparator:^NSComparisonResult(NSDictionary *x,
                                                          NSDictionary *y) {
        return [(x[@"due"] ?: @"") compare:(y[@"due"] ?: @"")];
    }];
    NSDictionary *doneMap = LoadDone();
    if (!self.sessionMarks) self.sessionMarks = [NSMutableSet set];
    NSMutableArray *pending = [NSMutableArray array];
    for (NSDictionary *a in feedAndTasks) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSDate *due = ParseISO(a[@"due"]);
        if (due && [due compare:now] == NSOrderedAscending) continue;
        [pending addObject:a];
    }

    NSMutableArray *todo = [NSMutableArray array];
    NSMutableArray *finished = [NSMutableArray array];
    for (NSDictionary *a in pending) {
        NSString *key = DoneKey(a);
        BOOL done = doneMap[key] != nil;
        if (done && self.schedule.hideDone &&
            ![self.sessionMarks containsObject:key]) continue;
        [(done ? finished : todo) addObject:a];
    }
    NSUInteger todoSlots = 0, doneSlots = 0;
    SplitAssignmentCap(todo.count, finished.count,
                       (NSUInteger)self.schedule.assignmentCap,
                       &todoSlots, &doneSlots);

    NSMutableArray *ordered = [NSMutableArray array];
    [ordered addObjectsFromArray:[todo subarrayWithRange:NSMakeRange(0, todoSlots)]];
    [ordered addObjectsFromArray:[finished subarrayWithRange:NSMakeRange(0, doneSlots)]];
    NSArray *up = ordered;

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
        CGFloat nw = [Clip(nm, 46) sizeWithAttributes:rowFont].width;
        if (nw > nameMax) nameMax = nw;
    }
    CGFloat dueWidth = ceil(dueMax);
    CGFloat cardWidth = MAX(292.0,
                            dueWidth + kDueColumnGap + ceil(nameMax) +
                            kDoneCircleWidth + 26.0);
    self.menuWidth = cardWidth;

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

            [menu addItem:AssignmentItem(a, dl, Clip(nm, 46),
                                         [ur isKindOfClass:[NSString class]] ? ur : @"",
                                         tip, late, doneMap[DoneKey(a)] != nil,
                                         dueWidth, cardWidth,
                                         self, @selector(toggleDone:))];
        }
    }

    if (self.composing) {
        if (!self.draftDue) {
            NSCalendar *cal2 = [NSCalendar currentCalendar];
            NSDateComponents *parts = [cal2 components:(NSCalendarUnitYear |
                NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
            parts.hour = 23;
            parts.minute = 59;
            self.draftDue = [cal2 dateFromComponents:parts] ?: now;
        }
        [menu addItem:ComposeRowItem(self.draftName ?: @"", self.draftDue,
                                     self.pickingDay, self,
                                     @selector(commitTask:), self,
                                     @selector(toggleDayPicker:), cardWidth)];
        if (self.pickingDay)
            [menu addItem:CalendarRowItem(self.draftDue, self,
                                          @selector(dayPicked:), cardWidth)];
    }

    FooterView *fv = [[FooterView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, 26)];
    fv.autoresizingMask = NSViewWidthSizable;
    fv.target = self;
    fv.quitAction = @selector(quitApp);
    fv.refreshAction = @selector(refreshNow);
    fv.settingsAction = @selector(openSettings);
    fv.plusAction = @selector(openQuickAdd);
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
    [self.settings setNote:text];
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

- (void)keepDraftFrom:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (![item.view isKindOfClass:[ComposeRowView class]]) continue;
        ComposeRowView *row = (ComposeRowView *)item.view;
        self.draftName = row.nameField.stringValue;
        self.draftDue = [row chosenDue];
        return;
    }
}

- (void)clearDraft {
    self.draftName = nil;
    self.draftDue = nil;
}

- (void)rebuildSoon {
    __weak ClassBar *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ClassBar *me = weak;
        NSMenu *m = me.liveMenu;
        if (me.menuOpen && m) [me menuNeedsUpdate:m];
    });
}

- (void)openQuickAdd {
    self.composing = !self.composing;
    if (!self.composing) { self.pickingDay = NO; [self clearDraft]; }
    [self rebuildSoon];
}

- (void)toggleDayPicker:(ComposeRowView *)row {
    self.draftName = row.nameField.stringValue;
    self.draftDue = [row chosenDue];
    self.pickingDay = !self.pickingDay;
    [self rebuildSoon];
}

- (void)dayPicked:(CalendarRowView *)row {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *day = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                             NSCalendarUnitDay)
                                   fromDate:row.calendar.dateValue];
    NSDateComponents *clock = [cal components:(NSCalendarUnitHour |
                                               NSCalendarUnitMinute)
                                     fromDate:self.draftDue ?: [NSDate date]];
    day.hour = clock.hour;
    day.minute = clock.minute;
    self.draftDue = [cal dateFromComponents:day] ?: self.draftDue;
    self.pickingDay = NO;
    [self rebuildSoon];
}

- (void)commitTask:(ComposeRowView *)row {
    NSString *name = row.nameField.stringValue;
    if (!row.cancelled && [name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]].length)
        AddTask(name, [row chosenDue]);
    self.composing = NO;
    self.pickingDay = NO;
    [self clearDraft];
    [self rebuildSoon];
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

    NSURL *url = FeedURL(feed);
    if (!url) {
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
    if (changed && self.menuOpen && !self.composing && m) [self menuNeedsUpdate:m];
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

- (void)toggleDone:(AssignmentView *)row {
    BOOL next = !row.done;
    NSString *key = DoneKey(row.item);
    SetDone(row.item, next);
    if (next) [self.sessionMarks addObject:key];
    else [self.sessionMarks removeObject:key];

    row.done = next;
    row.needsDisplay = YES;

    __weak ClassBar *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ClassBar *me = weak;
        NSMenu *m = me.liveMenu;
        if (!me.menuOpen || !m) return;
        [me menuNeedsUpdate:m];
        [me restoreHoverUnderCursor:m];
    });
}

- (void)restoreHoverUnderCursor:(NSMenu *)menu {
    NSPoint mouse = [NSEvent mouseLocation];
    for (NSMenuItem *item in menu.itemArray) {
        NSView *v = item.view;
        if (![v isKindOfClass:[HoverTipView class]] || !v.window) continue;
        NSRect onScreen = [v.window convertRectToScreen:
            [v convertRect:v.bounds toView:nil]];
        if (!NSPointInRect(mouse, onScreen)) continue;
        HoverTipView *hover = (HoverTipView *)v;
        [hover syncHoverAt:[v convertPoint:
            [v.window convertPointFromScreen:mouse] fromView:nil]];
        return;
    }
}

- (void)menuDidClose:(NSMenu *)menu __unused {
    self.menuOpen = NO;
    self.composing = NO;
    self.pickingDay = NO;
    [self clearDraft];
    [self.sessionMarks removeAllObjects];
    TipHide();
    [self refreshIfOlderThan:kRefreshFloorSeconds];
}

- (void)quitApp { [NSApp terminate:nil]; }

@end
