#import <Cocoa/Cocoa.h>
#import "app.h"
#import "views.h"
#import "settings.h"
#import "ics.h"
#import "schedule.h"
#import "store.h"

static int fails = 0;

static Schedule *FixtureSchedule(void) {
    NSString *canvas = @"https://example.instructure.com/courses/259102";
    return [Schedule loadFromDictionary:@{
        @"canvasHome": @"https://example.instructure.com/",
        @"term": @{ @"start": @20260909, @"end": @20261220,
                    @"beforeLabel": @"Classes begin Sep 9" },
        @"classes": @[
            @{ @"name": @"Gen Chem", @"code": @"CHEM 1151",
               @"room": @"Shillman Hall 105", @"days": @[@0, @2, @3],
               @"start": @"09:15", @"end": @"10:20", @"canvas": canvas },
            @{ @"name": @"CHEM Recitation", @"code": @"CHEM 1153",
               @"room": @"Robinson Hall 411", @"days": @[@0],
               @"start": @"11:45", @"end": @"12:50" },
            @{ @"name": @"Calculus 2", @"code": @"MATH 1342",
               @"room": @"Kariotis Hall 110", @"days": @[@0, @2, @3],
               @"start": @"13:35", @"end": @"14:40" },
            @{ @"name": @"Creative Writing", @"code": @"CRWT 1170",
               @"room": @"Online", @"days": @[@0, @2],
               @"start": @"14:50", @"end": @"16:30",
               @"zoom": @"https://example.instructure.com/zoom" },
            @{ @"name": @"Cornerstone 1", @"code": @"GE 1501",
               @"room": @"Snell 268", @"days": @[@0, @2, @3],
               @"start": @"16:35", @"end": @"17:40" },
        ],
    }];
}

static NSDate *ISODate(NSString *s) {
    return [ISOFormatter() dateFromString:s];
}

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
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        gSched = FixtureSchedule();

        if (argc > 1 && strcmp(argv[1], "--live") == 0) {
            SettingsWindow *sw = [[SettingsWindow alloc] init];
            [sw load];
            if (sw.feedField.stringValue.length)
                sw.feedField.stringValue = @"https://redacted.instructure.com/feeds/…";
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            [sw.window makeKeyAndOrderFront:nil];
            if (argc > 2 && strcmp(argv[2], "done") == 0) [sw openDoneSheet];
            printf("window %ld\n", (long)sw.window.windowNumber);
            fflush(stdout);
            [[NSRunLoop currentRunLoop] runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:25]];
            return 0;
        }

        if (argc > 2 && strcmp(argv[1], "--rows") == 0) {
            NSArray *rows = @[ @[@"today 11:59p", @"Chapter 5: Problem Definition", @0, @0],
                               @[@"tmr 9:15a", @"Reading guide 3.8 - 3.12", @0, @0],
                               @[@"2d", @"Week 2 - Upload your responses to poems", @0, @1],
                               @[@"late", @"Welcome Survey Confirmation", @1, @0] ];
            CGFloat w = 360, h = 22, pad = 10, dueWidth = 0;
            for (NSArray *r in rows) {
                CGFloat dw = [r[0] sizeWithAttributes:
                    @{ NSFontAttributeName: DueFont(YES) }].width;
                if (dw > dueWidth) dueWidth = ceil(dw);
            }
            NSImage *sheet = [[NSImage alloc]
                initWithSize:NSMakeSize(w + pad * 2, (h + 4) * rows.count + pad * 2 + 24)];
            [sheet lockFocus];
            [[NSColor colorWithWhite:0.13 alpha:1.0] setFill];
            NSRectFill(NSMakeRect(0, 0, sheet.size.width, sheet.size.height));
            for (NSUInteger i = 0; i < rows.count; i++) {
                NSArray *r = rows[i];
                AssignmentView *v = [[AssignmentView alloc]
                    initWithFrame:NSMakeRect(0, 0, w, h)];
                v.due = r[0];
                v.name = r[1];
                v.late = [r[2] boolValue];
                v.done = [r[3] boolValue];
                v.dueWidth = dueWidth;
                v.hovered = (i == 1);
                v.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
                NSRect slot = NSMakeRect(pad,
                                         sheet.size.height - pad - (h + 4) * (i + 1), w, h);
                [NSGraphicsContext saveGraphicsState];
                NSAffineTransform *t = [NSAffineTransform transform];
                [t translateXBy:NSMinX(slot) yBy:NSMinY(slot)];
                [t concat];
                [v displayRectIgnoringOpacity:v.bounds
                                    inContext:[NSGraphicsContext currentContext]];
                [NSGraphicsContext restoreGraphicsState];
            }
            [sheet unlockFocus];
            NSBitmapImageRep *out = [[NSBitmapImageRep alloc]
                initWithData:[sheet TIFFRepresentation]];
            BOOL ok = [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:@(argv[2]) atomically:YES];
            printf("%s %s (row 2 hovered)\n", ok ? "wrote" : "failed", argv[2]);
            return ok ? 0 : 1;
        }

        if (argc > 2 && strcmp(argv[1], "--footer") == 0) {
            NSArray *states = @[@"idle", @"quit", @"refresh", @"plus", @"gear"];
            CGFloat w = 300, h = 26, pad = 12;
            NSImage *sheet = [[NSImage alloc]
                initWithSize:NSMakeSize(w + pad * 2,
                                        (h + pad) * states.count + pad)];
            [sheet lockFocus];
            [[NSColor colorWithWhite:0.13 alpha:1.0] setFill];
            NSRectFill(NSMakeRect(0, 0, sheet.size.width, sheet.size.height));
            for (NSUInteger i = 0; i < states.count; i++) {
                FooterView *f = [[FooterView alloc]
                    initWithFrame:NSMakeRect(0, 0, w, h)];
                f.status = @"3h ago";
                NSString *st = states[i];
                f.hovered = ![st isEqualToString:@"idle"];
                f.overQuit = [st isEqualToString:@"quit"];
                f.overRefresh = [st isEqualToString:@"refresh"];
                f.overPlus = [st isEqualToString:@"plus"];
                f.overGear = [st isEqualToString:@"gear"];
                f.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
                NSRect slot = NSMakeRect(pad,
                                         sheet.size.height - pad - (h + pad) * (i + 1),
                                         w, h);
                [NSGraphicsContext saveGraphicsState];
                NSAffineTransform *shift = [NSAffineTransform transform];
                [shift translateXBy:NSMinX(slot) yBy:NSMinY(slot)];
                [shift concat];
                [f displayRectIgnoringOpacity:f.bounds
                                    inContext:[NSGraphicsContext currentContext]];
                [NSGraphicsContext restoreGraphicsState];
            }
            [sheet unlockFocus];
            NSBitmapImageRep *out = [[NSBitmapImageRep alloc]
                initWithData:[sheet TIFFRepresentation]];
            BOOL ok = [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:@(argv[2]) atomically:YES];
            printf("%s %s (%s)\n", ok ? "wrote" : "failed", argv[2],
                   [[states componentsJoinedByString:@", "] UTF8String]);
            return ok ? 0 : 1;
        }

        if (argc > 2 && strcmp(argv[1], "--shot") == 0) {
            SettingsWindow *sw = [[SettingsWindow alloc] init];
            [sw load];
            if (sw.feedField.stringValue.length)
                sw.feedField.stringValue = @"https://redacted.instructure.com/feeds/…";
            [sw.window setFrameOrigin:NSMakePoint(-5000, -5000)];
            [sw.window orderFrontRegardless];
            NSView *v = sw.window.contentView;
            [v layoutSubtreeIfNeeded];
            [[NSRunLoop currentRunLoop] runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:1.0]];
            [v displayIfNeeded];
            NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext =
                [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [v.layer renderInContext:NSGraphicsContext.currentContext.CGContext];
            [NSGraphicsContext restoreGraphicsState];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                            properties:@{}];
            BOOL ok = [png writeToFile:@(argv[2]) atomically:YES];
            printf("%s %s (%.0fx%.0f, %lu classes)\n", ok ? "wrote" : "failed", argv[2],
                   NSWidth(v.bounds), NSHeight(v.bounds),
                   (unsigned long)sw.classes.count);
            return ok ? 0 : 1;
        }

        if (argc > 1) {
            NSString *text = [NSString stringWithContentsOfFile:@(argv[1])
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
            if (!text) { printf("cannot read %s\n", argv[1]); return 1; }
            NSArray *all = cb_ics_items(text, gSched.canvasHome);
            NSArray *kept = cb_ics_window(all, [NSDate date], 0, 21, kCacheAssignmentCap);
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

        printf("schedule: fixture\n");
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
        T("Tue is free",              20260915, 700,  1, "no classes today!", "");
        T("Thu 6:00 PM (day over)",   20260917, 1080, 3, "done for the day! :3", "");
        T("Fri is free",              20260918, 700,  4, "no classes today!", "");
        T("Sun is free",              20260920, 700,  6, "no classes today!", "");
        T("Thu 10:30 -> Calculus",    20260917, 630,  3, "Calculus 2",      "1:35p • in 3h 5m");
        T("after term",               20261221, 600,  0, "Term is over",    "");

        printf("\ncb_series — current + next pairing\n");
        T2("Mon 9:30 in Gen Chem",    20260914, 570,  0, "Gen Chem", "CHEM Recitation");
        T2("Mon 4:00 in CRWT",        20260914, 960,  0, "Creative Writing", "Cornerstone 1");
        T2("Thu evening is done",     20260917, 1080, 3, "done for the day! :3", "");
        T2("Tue free shows one card", 20260915, 700,  1, "no classes today!", "");
        T2("Mon 5:00 last class",     20260914, 1020, 0, "Cornerstone 1", "done for the day! :3");
        T2("Mon 4:30 before last",    20260914, 990,  0, "Cornerstone 1", "done for the day! :3");
        T2("Thu 5:00 last class",     20260917, 1020, 3, "Cornerstone 1", "done for the day! :3");

        printf("\ndone-for-the-day tip\n");
        NSString *tip = cb_series(gSched, 20260914, 1080, 0, 1)[0][@"tip"];
        NSString *freeCardTip = cb_series(gSched, 20260915, 700, 1, 1)[0][@"tip"];
        BOOL tipOK = [tip isEqualToString:freeCardTip];
        printf("  %-4s done card and free day card share one tip\n", tipOK ? "ok" : "FAIL");
        if (!tipOK) { fails++; printf("       got [%s]\n", tip.UTF8String); }

        printf("\nfree day card\n");
        NSArray *freeDay = cb_series(gSched, 20260915, 700, 1, 2);
        NSString *freeTip = freeDay.count ? freeDay[0][@"tip"] : @"";
        struct { const char *label; BOOL ok; } freeChecks[] = {
            { "one card, not tomorrow's class", freeDay.count == 1 },
            { "names the next class day",       [freeTip hasPrefix:@"Next: Wednesday"] },
            { "lists every class that day",     [freeTip containsString:@"9:15a · Gen Chem"] &&
                  [freeTip containsString:@"1:35p · Calculus 2"] &&
                  [freeTip containsString:@"4:35p · Cornerstone 1"] },
            { "carries rooms",                  [freeTip containsString:@"Shillman Hall 105"] },
            { "skips the next free day",        [cb_series(gSched, 20260918, 700, 4, 1)[0][@"tip"]
                  hasPrefix:@"Next: Monday"] },
        };
        for (size_t i = 0; i < sizeof(freeChecks) / sizeof(freeChecks[0]); i++) {
            if (!freeChecks[i].ok) fails++;
            printf("  %-4s %s\n", freeChecks[i].ok ? "ok" : "FAIL", freeChecks[i].label);
        }

        printf("\nmarking work done\n");
        NSDictionary *withURL = @{ @"name": @"Chapter 5", @"due": @"2026-09-20T03:59:59Z",
                                   @"url": @"https://x.instructure.com/courses/1/assignments/2" };
        NSDictionary *noURL = @{ @"name": @"Write poem", @"course": @"CRWT 1170",
                                 @"due": @"2026-09-20T03:59:59Z" };
        NSDictionary *moved = @{ @"name": @"Write poem", @"course": @"CRWT 1170",
                                 @"due": @"2026-09-27T03:59:59Z" };
        NSDictionary *sameName = @{ @"name": @"Write poem", @"course": @"ENGW 1111",
                                    @"due": @"2026-09-20T03:59:59Z" };
        NSDate *anchorNow = ISODate(@"2026-09-15T00:00:00Z");
        NSDictionary *map = @{
            @"keep":  @"2026-09-20T03:59:59Z",
            @"stale": @"2026-09-10T03:59:59Z",
            @"undated": @"",
        };
        NSDictionary *pruned = PruneDone(map, anchorNow);
        struct { const char *label; BOOL ok; } doneChecks[] = {
            { "url is the key when present", [DoneKey(withURL) isEqualToString:
                  @"https://x.instructure.com/courses/1/assignments/2"] },
            { "falls back to name and course", [DoneKey(noURL) isEqualToString:
                  @"Write poem|CRWT 1170"] },
            { "key survives a due date change", [DoneKey(noURL)
                  isEqualToString:DoneKey(moved)] },
            { "same name, other course differs", ![DoneKey(noURL)
                  isEqualToString:DoneKey(sameName)] },
            { "null fields do not crash",    [DoneKey(@{ @"name": [NSNull null],
                                                         @"url": [NSNull null] })
                  isEqualToString:@"|"] },
            { "two items never collide",     ![DoneKey(withURL) isEqualToString:DoneKey(noURL)] },
            { "pending marks survive",       pruned[@"keep"] != nil },
            { "past due marks are pruned",   pruned[@"stale"] == nil },
            { "undated marks survive",       pruned[@"undated"] != nil },
            { "prune leaves the rest alone", pruned.count == 2 },
        };
        for (size_t i = 0; i < sizeof(doneChecks) / sizeof(doneChecks[0]); i++) {
            if (!doneChecks[i].ok) fails++;
            printf("  %-4s %s\n", doneChecks[i].ok ? "ok" : "FAIL", doneChecks[i].label);
        }

        printf("\ncap split between todo and done\n");
        struct { const char *label; NSUInteger todo, done, cap, wantTodo, wantDone; } splits[] = {
            { "few of each fit",            6,  2, 10, 6, 2 },
            { "done keeps the bottom rows", 17, 2, 10, 8, 2 },
            { "done backfills spare rows",  2, 20, 10, 2, 8 },
            { "done is halved when busy",  20, 20, 10, 5, 5 },
            { "no done work",               17, 0, 10, 10, 0 },
            { "nothing pending",            0,  3, 10, 0, 3 },
            { "empty",                      0,  0, 10, 0, 0 },
            { "cap of one favours todo",    5,  5,  1, 1, 0 },
            { "under cap shows all",        3,  1, 10, 3, 1 },
        };
        for (size_t i = 0; i < sizeof(splits) / sizeof(splits[0]); i++) {
            NSUInteger a = 0, b = 0;
            SplitAssignmentCap(splits[i].todo, splits[i].done, splits[i].cap, &a, &b);
            BOOL ok = a == splits[i].wantTodo && b == splits[i].wantDone &&
                      a + b <= splits[i].cap;
            if (!ok) fails++;
            printf("  %-4s %-28s %lu todo + %lu done\n", ok ? "ok" : "FAIL",
                   splits[i].label, (unsigned long)a, (unsigned long)b);
        }

        printf("\ntooltip shape\n");
        NSString *classTip = cb_series(gSched, 20260915, 700, 1, 1)[0][@"tip"];
        NSString *itemTip = TipText(@"Chapter 5: Problem Definition",
                                    @[@"GE1501.MERGED.202710",
                                      @"Due Sun Sep 13 · 11:59 PM"]);
        NSString *sparse = TipText(@"Just a heading", @[@"", @""]);
        struct { const char *label; BOOL ok; } shapeChecks[] = {
            { "heading is the first line",   [[classTip componentsSeparatedByString:@"\n"][0]
                                                 hasPrefix:@"Next: "] &&
                                             [[itemTip componentsSeparatedByString:@"\n"][0]
                                                 isEqualToString:
                                                     @"Chapter 5: Problem Definition"] },
            { "details use one separator",   [classTip containsString:@" · "] &&
                                             [itemTip containsString:@" · "] },
            { "no blank lines anywhere",     ![classTip containsString:@"\n\n"] &&
                                             ![itemTip containsString:@"\n\n"] &&
                                             ![sparse containsString:@"\n"] },
            { "empty parts are dropped",     [TipJoin(@[@"a", @"", @"b"])
                                                 isEqualToString:@"a · b"] },
            { "empty tip stays empty",       TipText(@"", @[@"", @""]).length == 0 },
        };
        for (size_t i = 0; i < sizeof(shapeChecks) / sizeof(shapeChecks[0]); i++) {
            if (!shapeChecks[i].ok) fails++;
            printf("  %-4s %s\n", shapeChecks[i].ok ? "ok" : "FAIL", shapeChecks[i].label);
        }

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
            @"BEGIN:VEVENT",
            @"UID:event-assignment-2@example.instructure.com",
            @"DTSTART;VALUE=DATE;VALUE=DATE:20260911",
            @"SUMMARY:Due at end of day [ENGW 1111]",
            @"END:VEVENT",
            @"END:VCALENDAR",
        ] componentsJoinedByString:@"\r\n"];

        NSArray *parsed = cb_ics_items(ics, @"https://example.instructure.com/");
        struct { const char *label; BOOL ok; } icsChecks[] = {
            { "calendar events are skipped",  parsed.count == 3 },
            { "sorted by due date",           parsed.count == 3 &&
                  [parsed[0][@"name"] hasPrefix:@"Reading response"] },
            { "folded summary is rejoined",   parsed.count == 3 &&
                  [parsed[1][@"name"] isEqualToString:
                      @"Week 2 - Upload Poems to be Workshopped"] },
            { "course is split off",          parsed.count == 3 &&
                  [parsed[1][@"course"] isEqualToString:@"CRWT 1170 Intro to Poetry"] },
            { "escapes are decoded",          parsed.count == 3 &&
                  [parsed[0][@"name"] isEqualToString:@"Reading response, part one"] },
            { "direct assignment url",        parsed.count == 3 &&
                  [parsed[1][@"url"] isEqualToString:
                      @"https://example.instructure.com/courses/260574/assignments/3409619"] },
            { "utc due time converted",       parsed.count == 3 &&
                  [ISOFormatter() dateFromString:parsed[1][@"due"]] != nil },
        };
        for (size_t i = 0; i < sizeof(icsChecks) / sizeof(icsChecks[0]); i++) {
            if (!icsChecks[i].ok) fails++;
            printf("  %-4s %s\n", icsChecks[i].ok ? "ok" : "FAIL", icsChecks[i].label);
        }

        NSDictionary *endOfDay = nil;
        for (NSDictionary *a in parsed)
            if ([a[@"name"] isEqualToString:@"Due at end of day"]) endOfDay = a;
        NSDate *eod = endOfDay ? [ISOFormatter() dateFromString:endOfDay[@"due"]] : nil;
        NSDateComponents *eodParts = eod ? [[NSCalendar currentCalendar]
            components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:eod] : nil;
        BOOL eodOK = eodParts && eodParts.hour == 23 && eodParts.minute == 59;
        if (!eodOK) fails++;
        printf("  %-4s date-only due time lands at 23:59 local\n", eodOK ? "ok" : "FAIL");

        NSDate *anchor = [ISOFormatter() dateFromString:@"2026-09-11T00:00:00Z"];
        BOOL windowOK = cb_ics_window(parsed, anchor, 14, 21, 25).count == 3 &&
                        cb_ics_window(parsed, anchor, 0, 21, 25).count == 2 &&
                        cb_ics_window(parsed, anchor, 14, 21, 1).count == 1;
        if (!windowOK) fails++;
        printf("  %-4s window trims by age, horizon, and cap\n", windowOK ? "ok" : "FAIL");

        BOOL pastOK = cb_ics_window(parsed, anchor, 0, 21, 25).count == 2;
        if (!pastOK) fails++;
        printf("  %-4s zero lookback drops past due work\n", pastOK ? "ok" : "FAIL");

        printf("\nday tokens\n");
        struct { const char *in; const char *want; } dayCases[] = {
            { "MWF",        "Mon Wed Fri" },
            { "TuTh",       "Tue Thu" },
            { "M W F",      "Mon Wed Fri" },
            { "mon, wed",   "Mon Wed" },
            { "MTWRF",      "Mon Tue Wed Thu Fri" },
            { "SaSu",       "Sat Sun" },
            { "",           "" },
            { "xyz",        "" },
        };
        for (size_t i = 0; i < sizeof(dayCases) / sizeof(dayCases[0]); i++) {
            NSString *got = DaysToText(TextToDays(@(dayCases[i].in)));
            BOOL ok = [got isEqualToString:@(dayCases[i].want)];
            if (!ok) fails++;
            printf("  %-4s %-10s -> %s\n", ok ? "ok" : "FAIL",
                   dayCases[i].in, got.UTF8String);
        }

        printf("\nclass import from ics\n");
        NSString *sched = [@[
            @"BEGIN:VCALENDAR",
            @"BEGIN:VEVENT",
            @"SUMMARY:PHYS 1151 - Physics for Engineering 1",
            @"LOCATION:Science Hall 210",
            @"DTSTART;TZID=America/New_York:20260909T091500",
            @"DTEND;TZID=America/New_York:20260909T102000",
            @"RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261220T000000Z",
            @"END:VEVENT",
            @"BEGIN:VEVENT",
            @"SUMMARY:Writing Seminar",
            @"LOCATION:Online",
            @"DTSTART:20260914T185000Z",
            @"DTEND:20260914T203000Z",
            @"END:VEVENT",
            @"BEGIN:VEVENT",
            @"SUMMARY:Writing Seminar",
            @"LOCATION:Online",
            @"DTSTART:20260916T185000Z",
            @"DTEND:20260916T203000Z",
            @"END:VEVENT",
            @"END:VCALENDAR",
        ] componentsJoinedByString:@"\r\n"];

        NSDictionary *imported = cb_ics_classes(sched);
        NSArray *cls = imported[@"classes"];
        NSDictionary *phys = nil, *writing = nil;
        for (NSDictionary *c in cls) {
            if ([c[@"code"] isEqualToString:@"PHYS 1151"]) phys = c;
            if ([c[@"name"] isEqualToString:@"Writing Seminar"]) writing = c;
        }
        struct { const char *label; BOOL ok; } classChecks[] = {
            { "two classes found",         cls.count == 2 },
            { "code split from title",     phys != nil &&
                  [phys[@"name"] isEqualToString:@"Physics for Engineering 1"] },
            { "rrule byday expanded",      phys != nil &&
                  [DaysToText(phys[@"days"]) isEqualToString:@"Mon Wed Fri"] },
            { "tzid clock preserved",      phys != nil &&
                  [phys[@"start"] isEqualToString:@"09:15"] },
            { "room read from location",   phys != nil &&
                  [phys[@"room"] isEqualToString:@"Science Hall 210"] },
            { "repeats merge into days",   writing != nil &&
                  [DaysToText(writing[@"days"]) isEqualToString:@"Mon Wed"] },
            { "utc converted to local",    writing != nil &&
                  [writing[@"start"] isEqualToString:@"14:50"] },
            { "term spans the rrule",      [imported[@"term"][@"start"] intValue] == 20260909 &&
                  [imported[@"term"][@"end"] intValue] == 20261220 },
            { "empty calendar returns nil", cb_ics_classes(@"BEGIN:VCALENDAR\r\nEND:VCALENDAR")
                  == nil },
        };
        for (size_t i = 0; i < sizeof(classChecks) / sizeof(classChecks[0]); i++) {
            if (!classChecks[i].ok) fails++;
            printf("  %-4s %s\n", classChecks[i].ok ? "ok" : "FAIL", classChecks[i].label);
        }

        printf("\nassignment cap\n");
        struct { const char *label; BOOL ok; } capChecks[] = {
            { "clamps below the minimum", ClampCap(0) == kMinAssignmentCap &&
                                          ClampCap(-5) == kMinAssignmentCap },
            { "clamps above the maximum", ClampCap(1000) == kMaxAssignmentCap },
            { "passes a sane value",      ClampCap(12) == 12 },
            { "default is in range",      ClampCap(kDefaultAssignmentCap) ==
                                          kDefaultAssignmentCap },
            { "cache holds more than the menu shows",
                                          kCacheAssignmentCap > kMaxAssignmentCap },
            { "schedule reads the cap",   gSched.assignmentCap >= kMinAssignmentCap &&
                                          gSched.assignmentCap <= kMaxAssignmentCap },
        };
        for (size_t i = 0; i < sizeof(capChecks) / sizeof(capChecks[0]); i++) {
            if (!capChecks[i].ok) fails++;
            printf("  %-4s %s\n", capChecks[i].ok ? "ok" : "FAIL", capChecks[i].label);
        }

        printf("\nsettings round trip\n");
        SettingsWindow *sw = [[SettingsWindow alloc] init];
        [sw load];
        [sw.window.contentView layoutSubtreeIfNeeded];
        NSDictionary *rebuilt = [sw buildRoot];
        NSMutableArray *mondays = [NSMutableArray array];
        for (NSDictionary *c in rebuilt[@"classes"])
            if ([c[@"days"] containsObject:@0]) [mondays addObject:c];

        struct { const char *label; BOOL ok; } tripChecks[] = {
            { "loads every class",     sw.classes.count ==
                  [[NSJSONSerialization JSONObjectWithData:
                      [NSData dataWithContentsOfFile:SchedulePath()]
                      options:0 error:NULL][@"classes"] count] },
            { "no validation problems", [sw problems].count == 0 },
            { "monday count matches",  mondays.count ==
                  [[Schedule loadFromDisk].byDay[0] count] },
            { "term survives",         [rebuilt[@"term"][@"start"] intValue] ==
                                       [Schedule loadFromDisk].termStart },
            { "feed field round trips", [rebuilt[@"canvasFeed"] isEqualToString:
                  sw.feedField.stringValue] },
            { "hide toggle round trips", [rebuilt[@"hideDone"] boolValue] ==
                  (sw.donePopup.indexOfSelectedItem == 1) },
            { "both modes are offered",  sw.donePopup.numberOfItems == 2 },
            { "hide toggle is on screen", sw.donePopup.superview != nil &&
                  NSWidth(sw.donePopup.frame) > 0 },
            { "date pickers are not clipped", NSWidth(sw.startPicker.frame) >= 118 &&
                  NSWidth(sw.endPicker.frame) >= 118 },
            { "popup hugs its title",  NSWidth(sw.donePopup.frame) <
                  NSWidth(sw.donePopup.superview.frame) },
            { "test button reports nearby", sw.feedStatus.superview != nil &&
                  sw.feedStatus.superview != sw.statusLabel.superview },
            { "days column fits four days", ({
                  NSTableColumn *col = nil;
                  for (NSTableColumn *c in sw.table.tableColumns)
                      if ([c.identifier isEqualToString:@"days"]) col = c;
                  CGFloat need = [DaysToText(@[@0, @2, @3, @6]) sizeWithAttributes:
                      @{ NSFontAttributeName: [NSFont systemFontOfSize:12] }].width;
                  col != nil && col.width >= need + 8; }) },
            { "labels are not clipped",    ({
                  BOOL fits = YES;
                  NSMutableArray *q = [@[sw.window.contentView] mutableCopy];
                  while (q.count) {
                      NSView *v = q.firstObject;
                      [q removeObjectAtIndex:0];
                      if ([v isKindOfClass:[NSTextField class]]) {
                          NSTextField *f = (NSTextField *)v;
                          if (!f.isEditable && f.stringValue.length &&
                              NSWidth(f.frame) > 0 &&
                              f.intrinsicContentSize.width > NSWidth(f.frame) + 0.5)
                              fits = NO;
                      }
                      [q addObjectsFromArray:v.subviews];
                  }
                  fits; }) },
            { "info tips carry their text", ({
                  NSMutableArray *tips = [NSMutableArray array];
                  NSMutableArray *queue = [@[sw.window.contentView] mutableCopy];
                  while (queue.count) {
                      NSView *v = queue.firstObject;
                      [queue removeObjectAtIndex:0];
                      if ([v isKindOfClass:[InfoTipView class]]) [tips addObject:v];
                      [queue addObjectsFromArray:v.subviews];
                  }
                  BOOL ok = tips.count == 2;
                  for (InfoTipView *t in tips)
                      ok = ok && t.tip.length > 0 &&
                           [[t accessibilityRole] isEqualToString:
                               NSAccessibilityButtonRole];
                  ok; }) },
            { "class cells centre their text", ({
                  NSView *box = [sw tableView:sw.table
                           viewForTableColumn:sw.table.tableColumns[0] row:0];
                  NSTextField *f = (NSTextField *)box.subviews.firstObject;
                  box.frame = NSMakeRect(0, 0, 120, 22);
                  [box layoutSubtreeIfNeeded];
                  fabs(NSMidY(f.frame) - NSMidY(box.bounds)) < 1.0; }) },
            { "restores stage until save", ({ [sw openDoneSheet];
                  NSUInteger before = DoneEntries().count;
                  [sw restoreAll];
                  BOOL staged = DoneEntries().count == before &&
                                sw.doneRows.count == 0;
                  [sw load];
                  BOOL discarded = sw.pendingRestores.count == 0 &&
                                   DoneEntries().count == before;
                  [sw closeDoneSheet];
                  staged && discarded; }) },
            { "restore sheet opens",   ({ [sw openDoneSheet];
                  BOOL built = sw.doneSheet != nil && sw.doneTable.numberOfColumns == 2;
                  [sw closeDoneSheet];
                  built; }) },
            { "cap round trips",       [rebuilt[@"assignmentCap"] intValue] ==
                  ClampCap(sw.capField.intValue) },
            { "typed junk clamps",     ({ [sw setCap:9999];
                  BOOL high = [[sw buildRoot][@"assignmentCap"] intValue] ==
                      kMaxAssignmentCap;
                  [sw setCap:0];
                  BOOL low = [[sw buildRoot][@"assignmentCap"] intValue] ==
                      kMinAssignmentCap;
                  [sw load];
                  high && low; }) },
            { "serialises to json",    [NSJSONSerialization
                  isValidJSONObject:rebuilt] },
            { "a fresh load is clean", ({ [sw load]; ![sw hasUnsavedChanges]; }) },
            { "an edit reads as dirty", ({
                  sw.homeField.stringValue = @"https://edited.example.com/";
                  BOOL dirty = [sw hasUnsavedChanges];
                  [sw load];
                  dirty && ![sw hasUnsavedChanges]; }) },
            { "a staged restore is dirty", ({
                  [sw.pendingRestores addObject:@"someKey"];
                  BOOL dirty = [sw hasUnsavedChanges];
                  [sw load];
                  dirty && ![sw hasUnsavedChanges]; }) },
        };
        for (size_t i = 0; i < sizeof(tripChecks) / sizeof(tripChecks[0]); i++) {
            if (!tripChecks[i].ok) fails++;
            printf("  %-4s %s\n", tripChecks[i].ok ? "ok" : "FAIL", tripChecks[i].label);
        }

        printf("\ncompose row\n");
        NSCalendar *rowCal = [NSCalendar currentCalendar];
        NSDateComponents *rowParts = [[NSDateComponents alloc] init];
        rowParts.year = 2026; rowParts.month = 9; rowParts.day = 22;
        rowParts.hour = 17; rowParts.minute = 30;
        NSDate *rowDue = [rowCal dateFromComponents:rowParts];
        NSMenuItem *rowItem = ComposeRowItem(@"draft", rowDue, nil, NULL, nil, NULL, 372);
        ComposeRowView *row = (ComposeRowView *)rowItem.view;
        [row layoutSubtreeIfNeeded];
        NSDateComponents *chosen = [rowCal components:(NSCalendarUnitYear |
            NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour |
            NSCalendarUnitMinute) fromDate:[row chosenDue]];
        struct { const char *label; BOOL ok; } rowChecks[] = {
            { "name, day and time",     row.nameField != nil && row.dayChip != nil &&
                                        row.timeChip != nil },
            { "day and time combine",   chosen.month == 9 && chosen.day == 22 &&
                                        chosen.hour == 17 && chosen.minute == 30 },
            { "the day reads as a chip", row.dayChip.stringValue.length > 0 &&
                  [row.dayChip.stringValue containsString:@"/"] },
            { "day and time recombine", ({
                  NSCalendar *c2 = [NSCalendar currentCalendar];
                  NSDateComponents *dp = [[NSDateComponents alloc] init];
                  dp.year = 2026; dp.month = 10; dp.day = 3;
                  NSDateComponents *tp = [[NSDateComponents alloc] init];
                  tp.year = 2001; tp.month = 2; tp.day = 2;
                  tp.hour = 8; tp.minute = 45;
                  NSDate *mix = CombineDayAndTime([c2 dateFromComponents:dp],
                                                  [c2 dateFromComponents:tp]);
                  NSDateComponents *got2 = [c2 components:(NSCalendarUnitYear |
                      NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour |
                      NSCalendarUnitMinute) fromDate:mix];
                  got2.year == 2026 && got2.month == 10 && got2.day == 3 &&
                  got2.hour == 8 && got2.minute == 45; }) },
            { "a calendar row exists",  ({
                  NSMenuItem *cal = CalendarRowItem(rowDue, nil, NULL, 372);
                  CalendarRowView *cv = (CalendarRowView *)cal.view;
                  cv.calendar != nil && cv.calendar.datePickerStyle ==
                      NSDatePickerStyleClockAndCalendar; }) },
            { "commit fires once",      ({ [row commit]; BOOL first = row.committed;
                                           [row commit]; first; }) },
            { "focus loss does not add", ({
                  NSMenuItem *it2 = ComposeRowItem(@"typed", rowDue, nil, NULL, nil, NULL, 372);
                  ComposeRowView *r2 = (ComposeRowView *)it2.view;
                  r2.nameField.target != nil || r2.nameField.action != NULL
                      ? NO : YES; }) },
            { "return commits",          ({
                  NSMenuItem *it3 = ComposeRowItem(@"typed", rowDue, nil, NULL, nil, NULL, 372);
                  ComposeRowView *r3 = (ComposeRowView *)it3.view;
                  NSTextView *probe3 = [[NSTextView alloc] init];
                  [r3 control:r3.nameField textView:probe3
                      doCommandBySelector:@selector(insertNewline:)];
                  r3.committed && !r3.cancelled; }) },
            { "escape cancels",          ({
                  NSMenuItem *it4 = ComposeRowItem(@"typed", rowDue, nil, NULL, nil, NULL, 372);
                  ComposeRowView *r4 = (ComposeRowView *)it4.view;
                  NSTextView *probe4 = [[NSTextView alloc] init];
                  [r4 control:r4.nameField textView:probe4
                      doCommandBySelector:@selector(cancelOperation:)];
                  r4.committed && r4.cancelled; }) },
            { "a draft is restored",    [row.nameField.stringValue
                  isEqualToString:@"draft"] },
            { "fields do not overlap",  NSMaxX(row.nameField.frame) <=
                  NSMinX(row.dayChip.frame) + 1 &&
                  NSMaxX(row.dayChip.frame) <= NSMinX(row.timeChip.frame) + 1 },
            { "the time reads as a chip", row.timeChip.stringValue.length > 0 &&
                  ([row.timeChip.stringValue containsString:@"AM"] ||
                   [row.timeChip.stringValue containsString:@"PM"]) },

        };
        for (size_t i = 0; i < sizeof(rowChecks) / sizeof(rowChecks[0]); i++) {
            if (!rowChecks[i].ok) fails++;
            printf("  %-4s %s\n", rowChecks[i].ok ? "ok" : "FAIL", rowChecks[i].label);
        }

        printf("\nquick tasks\n");
        NSDate *taskNow = ISODate(@"2026-09-15T00:00:00Z");
        NSArray *rawTasks = @[
            @{ @"name": @"Write poem", @"due": @"2026-09-20T03:59:59Z" },
            @{ @"name": @"Old thing",  @"due": @"2026-09-10T03:59:59Z" },
            @{ @"name": @"",           @"due": @"2026-09-20T03:59:59Z" },
            @{ @"name": @"No date" },
            @"junk",
        ];
        NSArray *keptTasks = PruneTasks(rawTasks, taskNow);
        struct { const char *label; BOOL ok; } taskChecks[] = {
            { "pending tasks survive",   keptTasks.count == 2 },
            { "past due tasks are gone", ({ BOOL none = YES;
                  for (NSDictionary *t in keptTasks)
                      if ([t[@"name"] isEqualToString:@"Old thing"]) none = NO;
                  none; }) },
            { "nameless tasks dropped",  ({ BOOL none = YES;
                  for (NSDictionary *t in keptTasks)
                      if (![t[@"name"] length]) none = NO;
                  none; }) },
            { "undated tasks survive",   ({ BOOL found = NO;
                  for (NSDictionary *t in keptTasks)
                      if ([t[@"name"] isEqualToString:@"No date"]) found = YES;
                  found; }) },
            { "junk is ignored",         keptTasks.count == 2 },
            { "tasks are marked",        [keptTasks.firstObject[@"task"] boolValue] },
            { "a task can be marked done", [DoneKey(keptTasks.firstObject)
                  isEqualToString:@"Write poem|"] },
        };
        for (size_t i = 0; i < sizeof(taskChecks) / sizeof(taskChecks[0]); i++) {
            if (!taskChecks[i].ok) fails++;
            printf("  %-4s %s\n", taskChecks[i].ok ? "ok" : "FAIL", taskChecks[i].label);
        }

        printf("\nreading a due date out of a name\n");
        NSDateComponents *baseParts = [[NSDateComponents alloc] init];
        baseParts.year = 2026; baseParts.month = 9; baseParts.day = 16;
        baseParts.hour = 10;
        NSDate *base = [[NSCalendar currentCalendar] dateFromComponents:baseParts];
        struct {
            const char *in; const char *wantName; int mon, day, hour, minute;
        } dueCases2[] = {
            { "finish lab report tomorrow 5pm", "finish lab report", 9, 17, 17, 0 },
            { "read chapter 4 today",           "read chapter 4",    9, 16, 23, 59 },
            { "essay friday",                   "essay",             9, 18, 23, 59 },
            { "gym tonight",                    "gym",               9, 16, 20, 0 },
            { "lunch noon",                     "lunch",             9, 16, 12, 0 },
            { "pset 9/22",                      "pset",              9, 22, 23, 59 },
            { "call mom 5:30pm",                "call mom",          9, 16, 17, 30 },
            { "pset td",                        "pset",              9, 16, 23, 59 },
            { "pset td 5p",                     "pset",              9, 16, 17, 0 },
            { "standup 9a",                     "standup",           9, 16, 9, 0 },
            { "review 11:30p",                  "review",            9, 16, 23, 30 },
        };
        for (size_t i = 0; i < sizeof(dueCases2) / sizeof(dueCases2[0]); i++) {
            NSString *clean = nil;
            NSDate *got4 = ParseDueFromText(@(dueCases2[i].in), base, &clean);
            NSDateComponents *c4 = got4 ? [[NSCalendar currentCalendar]
                components:(NSCalendarUnitMonth | NSCalendarUnitDay |
                            NSCalendarUnitHour | NSCalendarUnitMinute)
                  fromDate:got4] : nil;
            BOOL ok5 = got4 != nil && [clean isEqualToString:@(dueCases2[i].wantName)] &&
                       c4.month == dueCases2[i].mon && c4.day == dueCases2[i].day &&
                       c4.hour == dueCases2[i].hour && c4.minute == dueCases2[i].minute;
            if (!ok5) fails++;
            printf("  %-4s %-32s -> %s\n", ok5 ? "ok" : "FAIL",
                   dueCases2[i].in, clean.UTF8String);
        }
        NSString *untouched = nil;
        BOOL plain = ParseDueFromText(@"write the essay", base, &untouched) == nil &&
                     [untouched isEqualToString:@"write the essay"];
        if (!plain) fails++;
        printf("  %-4s plain text keeps its name\n", plain ? "ok" : "FAIL");

        printf("\ntyping a time\n");
        struct { const char *in; int want; } timeCases[] = {
            { "5",        5 * 60 },
            { "5pm",      17 * 60 },
            { "5 PM",     17 * 60 },
            { "5:30pm",   17 * 60 + 30 },
            { "17:30",    17 * 60 + 30 },
            { "1730",     17 * 60 + 30 },
            { "11:59 PM", 23 * 60 + 59 },
            { "12am",     0 },
            { "12pm",     12 * 60 },
            { "9:05a",    9 * 60 + 5 },
            { "",         -1 },
            { "banana",   -1 },
            { "25:00",    -1 },
            { "5:70",     -1 },
        };
        for (size_t i = 0; i < sizeof(timeCases) / sizeof(timeCases[0]); i++) {
            int got3 = ParseTimeText(@(timeCases[i].in));
            BOOL ok3 = got3 == timeCases[i].want;
            if (!ok3) fails++;
            printf("  %-4s %-10s -> %d\n", ok3 ? "ok" : "FAIL",
                   timeCases[i].in, got3);
        }

        printf("\ndue labels\n");
        NSDate *todayNoon = nil;
        [[NSCalendar currentCalendar] rangeOfUnit:NSCalendarUnitDay
                                        startDate:&todayNoon interval:NULL
                                          forDate:[NSDate date]];
        NSString *todayLabel = DueLabel([NSCalendar currentCalendar],
            [todayNoon dateByAddingTimeInterval:9 * 3600 + 15 * 60]);
        BOOL shortToday = ![todayLabel containsString:@"today"] &&
                          [todayLabel containsString:@":"];
        if (!shortToday) fails++;
        printf("  %-4s today is just the clock time   %s\n",
               shortToday ? "ok" : "FAIL", todayLabel.UTF8String);

        NSCalendar *dueCal = [NSCalendar currentCalendar];
        NSDate *midnight = nil;
        [dueCal rangeOfUnit:NSCalendarUnitDay startDate:&midnight
                   interval:NULL forDate:[NSDate date]];
        struct { const char *label; int addDays; } dueCases[] = {
            { "a week out is numeric", 8 },
            { "far out is numeric",   40 },
        };
        for (size_t i = 0; i < sizeof(dueCases) / sizeof(dueCases[0]); i++) {
            NSDateComponents *add = [[NSDateComponents alloc] init];
            add.day = dueCases[i].addDays;
            NSDate *d = [dueCal dateByAddingComponents:add toDate:midnight options:0];
            NSString *shown = DueLabel(dueCal, d);
            NSDateComponents *md = [dueCal components:
                (NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:d];
            NSString *want = [NSString stringWithFormat:@"%ld/%ld",
                              (long)md.month, (long)md.day];
            BOOL ok = [shown isEqualToString:want];
            if (!ok) fails++;
            printf("  %-4s %-24s %s\n", ok ? "ok" : "FAIL",
                   dueCases[i].label, shown.UTF8String);
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
