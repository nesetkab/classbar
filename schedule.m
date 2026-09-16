#import <Cocoa/Cocoa.h>
#import "schedule.h"
#import "store.h"

int ParseClock(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return -1;
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if (parts.count != 2) return -1;
    int h = [parts[0] intValue], m = [parts[1] intValue];
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
}

@implementation Schedule

+ (instancetype)loadFromDisk {
    NSData *d = [NSData dataWithContentsOfFile:SchedulePath()];
    if (!d) return [self failedWith:@"no schedule.json"];
    NSError *err = nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
    if (![root isKindOfClass:[NSDictionary class]])
        return [self failedWith:err ? @"schedule.json is not valid JSON"
                                    : @"schedule.json is malformed"];
    return [self loadFromDictionary:root];
}

+ (instancetype)failedWith:(NSString *)message {
    Schedule *s = [[Schedule alloc] init];
    s.loadError = message;
    s.byDay = @[@[], @[], @[], @[], @[], @[], @[]];
    return s;
}

+ (instancetype)loadFromDictionary:(NSDictionary *)root {
    Schedule *s = [[Schedule alloc] init];
    s.canvasHome = @"https://canvas.instructure.com/";
    s.termStart = 0;
    s.termEnd = 99999999;
    s.beforeLabel = @"term hasn't started";
    s.assignmentCap = kDefaultAssignmentCap;

    if ([root[@"canvasHome"] isKindOfClass:[NSString class]]) s.canvasHome = root[@"canvasHome"];
    if ([root[@"canvasFeed"] isKindOfClass:[NSString class]]) s.canvasFeed = root[@"canvasFeed"];
    if ([root[@"hideDone"] isKindOfClass:[NSNumber class]])
        s.hideDone = [root[@"hideDone"] boolValue];
    if ([root[@"assignmentCap"] isKindOfClass:[NSNumber class]])
        s.assignmentCap = ClampCap([root[@"assignmentCap"] intValue]);
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

const char * const kDayName[7] = {
    "monday","tuesday","wednesday","thursday","friday","saturday","sunday"
};

static NSDictionary *cb_notice(NSString *title, NSString *when) {
    return @{ @"title": title, @"code": @"", @"when": when ?: @"",
              @"room": @"", @"link": @"", @"zoom": @"", @"now": @NO,
              @"notice": @YES };
}

NSString *TipText(NSString *heading, NSArray *lines) {
    NSMutableArray *out = [NSMutableArray array];
    if (heading.length) [out addObject:heading];
    for (NSString *l in lines) if (l.length) [out addObject:l];
    return [out componentsJoinedByString:@"\n"];
}

NSString *TipJoin(NSArray *parts) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [out addObject:p];
    return [out componentsJoinedByString:@" · "];
}

static NSString *TipClassLine(NSDictionary *c) {
    return TipJoin(@[HHMMshort([c[@"start"] intValue]), c[@"name"], c[@"room"] ?: @""]);
}

static NSString *cb_next_day_tip(Schedule *s, int day) {
    for (int k = 1; k <= 7; k++) {
        int nd = (day + k) % 7;
        NSArray *list = s.byDay[nd];
        if (!list.count) continue;
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *c in list) [lines addObject:TipClassLine(c)];
        return TipText([NSString stringWithFormat:@"next: %s", kDayName[nd]], lines);
    }
    return @"";
}

static NSDictionary *cb_done(Schedule *s, int day) {
    NSMutableDictionary *m = [cb_notice(@"done for the day! :3", @"") mutableCopy];
    m[@"tip"] = cb_next_day_tip(s, day);
    m[@"done"] = @YES;
    return m;
}

NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count) {
    NSMutableArray *out = [NSMutableArray array];
    if (s.loadError)
        return @[cb_notice(s.loadError, @"add one to Application Support/classbar")];
    if (ymd < s.termStart) return @[cb_notice(@"term hasn't started", s.beforeLabel)];
    if (ymd > s.termEnd)   return @[cb_notice(@"term is over", @"")];

    if (![s.byDay[day] count]) {
        NSString *tip = cb_next_day_tip(s, day);
        if (tip.length) {
            NSMutableDictionary *m = [cb_notice(@"no classes today!", @"") mutableCopy];
            m[@"tip"] = tip;
            m[@"done"] = @YES;
            return @[m];
        }
    }

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
                @"now": @(now),
                @"progress": @(now && en > st ? (double)(mins - st) / (en - st) : 0.0)
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
    if (!out.count) return @[cb_notice(@"no classes", @"")];
    return out;
}

static NSArray *DayTokens(void) {
    return @[@"mon", @"tue", @"wed", @"thu", @"fri", @"sat", @"sun"];
}

NSString *DaysToText(NSArray *days) {
    NSArray *tokens = DayTokens();
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *d in days) {
        NSInteger i = d.integerValue;
        if (i >= 0 && i < 7) [out addObject:tokens[i]];
    }
    return [out componentsJoinedByString:@" "];
}

NSArray *TextToDays(NSString *text) {
    NSMutableString *letters = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 'a' && c <= 'z') c = (unichar)(c - 'a' + 'A');
        if (c >= 'A' && c <= 'Z') [letters appendFormat:@"%C", c];
    }
    NSArray *pairs = @[@"MO", @"TU", @"WE", @"TH", @"FR", @"SA", @"SU"];
    NSString *singles = @"MTWRFSU";
    NSMutableIndexSet *found = [NSMutableIndexSet indexSet];
    NSUInteger i = 0;
    while (i < letters.length) {
        NSUInteger pair = NSNotFound;
        if (i + 1 < letters.length)
            pair = [pairs indexOfObject:[letters substringWithRange:NSMakeRange(i, 2)]];
        if (pair != NSNotFound) {
            [found addIndex:pair];
            i += 2;
            continue;
        }
        NSRange one = [singles rangeOfString:[letters substringWithRange:NSMakeRange(i, 1)]];
        if (one.location != NSNotFound) [found addIndex:one.location];
        i += 1;
    }
    NSMutableArray *out = [NSMutableArray array];
    [found enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop __unused) {
        [out addObject:@(idx)];
    }];
    return out;
}
