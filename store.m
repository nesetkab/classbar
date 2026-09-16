#import <Cocoa/Cocoa.h>
#import "store.h"

NSString *SchedulePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/schedule.json"];
}

NSString *CachePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Caches/classbar/assignments.json"];
}

const int kDefaultAssignmentCap = 25;
const int kMinAssignmentCap = 1;
const int kMaxAssignmentCap = 100;
const int kCacheAssignmentCap = 200;

int ClampCap(int n) {
    if (n < kMinAssignmentCap) return kMinAssignmentCap;
    if (n > kMaxAssignmentCap) return kMaxAssignmentCap;
    return n;
}

void SplitAssignmentCap(NSUInteger todo, NSUInteger done, NSUInteger cap,
                        NSUInteger *todoShown, NSUInteger *doneShown) {
    NSUInteger forDone = MIN(done, cap / 2);
    NSUInteger forTodo = MIN(todo, cap - forDone);
    if (forTodo + forDone < cap) forDone = MIN(done, cap - forTodo);
    *todoShown = forTodo;
    *doneShown = forDone;
}

int ParseTimeText(NSString *text) {
    NSString *low = [[text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (!low.length) return -1;

    BOOL hasAM = [low containsString:@"a"];
    BOOL hasPM = [low containsString:@"p"];

    NSMutableString *digits = [NSMutableString string];
    BOOL sawColon = NO;
    for (NSUInteger i = 0; i < low.length; i++) {
        unichar c = [low characterAtIndex:i];
        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
        else if (c == ':') sawColon = YES;
    }
    if (!digits.length) return -1;

    int hour = 0, minute = 0;
    if (sawColon) {
        NSArray *parts = [low componentsSeparatedByString:@":"];
        if (parts.count < 2) return -1;
        hour = [parts[0] intValue];
        minute = [[parts[1] stringByTrimmingCharactersInSet:
            [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] intValue];
    } else if (digits.length <= 2) {
        hour = digits.intValue;
    } else {
        hour = [[digits substringToIndex:digits.length - 2] intValue];
        minute = [[digits substringFromIndex:digits.length - 2] intValue];
    }

    if (hasPM && hour < 12) hour += 12;
    if (hasAM && hour == 12) hour = 0;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
}

static NSInteger WeekdayWord(NSString *word) {
    NSArray *full = @[@"monday", @"tuesday", @"wednesday", @"thursday",
                      @"friday", @"saturday", @"sunday"];
    NSArray *brief = @[@"mon", @"tue", @"wed", @"thu", @"fri", @"sat", @"sun"];
    NSUInteger i = [full indexOfObject:word];
    if (i != NSNotFound) return (NSInteger)i;
    i = [brief indexOfObject:word];
    return i == NSNotFound ? -1 : (NSInteger)i;
}

static BOOL MonthDayWord(NSString *word, NSInteger *month, NSInteger *day) {
    NSArray *parts = [word componentsSeparatedByString:@"/"];
    if (parts.count < 2 || parts.count > 3) return NO;
    for (NSString *p in parts) {
        if (!p.length) return NO;
        for (NSUInteger i = 0; i < p.length; i++) {
            unichar c = [p characterAtIndex:i];
            if (c < '0' || c > '9') return NO;
        }
    }
    *month = [parts[0] integerValue];
    *day = [parts[1] integerValue];
    return *month >= 1 && *month <= 12 && *day >= 1 && *day <= 31;
}

static BOOL LooksLikeTime(NSString *word) {
    if ([word containsString:@":"]) return YES;
    return [word hasSuffix:@"am"] || [word hasSuffix:@"pm"] ||
           [word hasSuffix:@"a"] || [word hasSuffix:@"p"];
}

NSDate *ParseDueFromText(NSString *text, NSDate *now, NSString **cleaned) {
    if (cleaned) *cleaned = text;
    if (!text.length) return nil;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSArray *words = [text componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    NSMutableIndexSet *eaten = [NSMutableIndexSet indexSet];

    NSInteger shift = -1, weekday = -1, month = -1, monthDay = -1;
    int minutes = -1;

    for (NSUInteger i = 0; i < words.count; i++) {
        NSString *word = [[words[i] stringByTrimmingCharactersInSet:
            [NSCharacterSet punctuationCharacterSet]] lowercaseString];
        if (!word.length) continue;

        if ([word isEqualToString:@"today"]) {
            shift = 0; [eaten addIndex:i]; continue;
        }
        if ([word isEqualToString:@"tonight"]) {
            shift = 0;
            if (minutes < 0) minutes = 20 * 60;
            [eaten addIndex:i]; continue;
        }
        if ([word isEqualToString:@"tomorrow"] || [word isEqualToString:@"tmr"] ||
            [word isEqualToString:@"tmrw"]) {
            shift = 1; [eaten addIndex:i]; continue;
        }
        if ([word isEqualToString:@"noon"]) {
            minutes = 12 * 60; [eaten addIndex:i]; continue;
        }
        if ([word isEqualToString:@"midnight"]) {
            minutes = 23 * 60 + 59; [eaten addIndex:i]; continue;
        }

        NSInteger wd = WeekdayWord(word);
        if (wd >= 0) { weekday = wd; [eaten addIndex:i]; continue; }

        NSInteger m2 = -1, d2 = -1;
        if (MonthDayWord(word, &m2, &d2)) {
            month = m2; monthDay = d2; [eaten addIndex:i]; continue;
        }

        if (LooksLikeTime(word)) {
            int parsed = ParseTimeText(word);
            if (parsed >= 0) { minutes = parsed; [eaten addIndex:i]; continue; }
        }
    }

    if (!eaten.count) return nil;

    NSDateComponents *base = [cal components:(NSCalendarUnitYear |
        NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
    NSDate *day = [cal dateFromComponents:base];

    if (weekday >= 0) {
        NSInteger todayIndex = [cal component:NSCalendarUnitWeekday fromDate:now] - 2;
        if (todayIndex < 0) todayIndex = 6;
        NSInteger ahead = weekday - todayIndex;
        if (ahead <= 0) ahead += 7;
        NSDateComponents *add = [[NSDateComponents alloc] init];
        add.day = ahead;
        day = [cal dateByAddingComponents:add toDate:day options:0];
    } else if (month > 0) {
        NSDateComponents *pick = [cal components:NSCalendarUnitYear fromDate:now];
        pick.month = month;
        pick.day = monthDay;
        NSDate *made = [cal dateFromComponents:pick];
        if (made && [made compare:day] == NSOrderedAscending) {
            pick.year += 1;
            made = [cal dateFromComponents:pick];
        }
        if (made) day = made;
    } else if (shift > 0) {
        NSDateComponents *add = [[NSDateComponents alloc] init];
        add.day = shift;
        day = [cal dateByAddingComponents:add toDate:day options:0];
    }

    NSDateComponents *out = [cal components:(NSCalendarUnitYear |
        NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:day];
    out.hour = minutes >= 0 ? minutes / 60 : 23;
    out.minute = minutes >= 0 ? minutes % 60 : 59;

    if (cleaned) {
        NSMutableArray *kept = [NSMutableArray array];
        for (NSUInteger i = 0; i < words.count; i++)
            if (![eaten containsIndex:i] && [words[i] length]) [kept addObject:words[i]];
        *cleaned = [kept componentsJoinedByString:@" "];
    }
    return [cal dateFromComponents:out];
}

NSString *HHMMshort(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d%s", h, mm, h24 >= 12 ? "p" : "a"];
}

NSISO8601DateFormatter *ISOFormatter(void) {
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
    return f;
}

BOOL WriteCache(NSArray *items) {
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

NSArray *LoadUpcoming(void) {
    id items = LoadCache()[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

NSString *CacheAgeLabel(void) {
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

NSDate *ParseISO(NSString *s) {
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

NSString *DueLabel(NSCalendar *cal, NSDate *due) {
    if (!due) return @"";
    NSDate *a, *b;
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&a interval:NULL forDate:[NSDate date]];
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&b interval:NULL forDate:due];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:a toDate:b options:0] day];

    NSDateComponents *tc = [cal components:(NSCalendarUnitHour|NSCalendarUnitMinute)
                                  fromDate:due];
    NSString *clock = HHMMshort((int)tc.hour * 60 + (int)tc.minute);

    if (days < 0)  return @"late";
    if (days == 0) return clock;
    if (days == 1) return [NSString stringWithFormat:@"tmr %@", clock];
    if (days < 7)  return [NSString stringWithFormat:@"%ldd", (long)days];

    NSDateComponents *c = [cal components:(NSCalendarUnitMonth|NSCalendarUnitDay)
                                 fromDate:due];
    return [NSString stringWithFormat:@"%ld/%ld", (long)c.month, (long)c.day];
}

NSString *Clip(NSString *s, NSUInteger n) {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length <= n) return s;
    return [[s substringToIndex:n - 1] stringByAppendingString:@"…"];
}

NSDate *EndOfDay(NSDate *date) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                           NSCalendarUnitDay)
                                 fromDate:date];
    c.hour = 23;
    c.minute = 59;
    c.second = 59;
    return [cal dateFromComponents:c] ?: date;
}

NSDate *CombineDayAndTime(NSDate *day, NSDate *time) {
    if (!day) return time;
    if (!time) return day;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *parts = [cal components:(NSCalendarUnitYear |
        NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:day];
    NSDateComponents *clock = [cal components:(NSCalendarUnitHour |
        NSCalendarUnitMinute) fromDate:time];
    parts.hour = clock.hour;
    parts.minute = clock.minute;
    parts.second = 0;
    return [cal dateFromComponents:parts] ?: day;
}

NSURL *FeedURL(NSString *raw) {
    NSString *feed = [raw stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!feed.length) return nil;
    if ([feed hasPrefix:@"webcal://"])
        feed = [@"https://" stringByAppendingString:[feed substringFromIndex:9]];
    NSURL *url = [NSURL URLWithString:feed];
    return url.host ? url : nil;
}

NSString *DonePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/done.json"];
}

static NSString *StringField(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

NSString *DoneKey(NSDictionary *item) {
    NSString *url = StringField(item, @"url");
    if (url.length) return url;
    return [NSString stringWithFormat:@"%@|%@",
            StringField(item, @"name"), StringField(item, @"course")];
}

static NSDictionary *DoneEntry(id value) {
    if ([value isKindOfClass:[NSDictionary class]])
        return @{ @"due": StringField(value, @"due"),
                  @"name": StringField(value, @"name") };
    if ([value isKindOfClass:[NSString class]]) return @{ @"due": value, @"name": @"" };
    return nil;
}

NSDictionary *PruneDone(NSDictionary *map, NSDate *now) {
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    for (NSString *key in map) {
        NSDictionary *entry = DoneEntry(map[key]);
        if (!entry) continue;
        NSDate *due = ParseISO(entry[@"due"]);
        if (due && [due compare:now] == NSOrderedAscending) continue;
        kept[key] = entry;
    }
    return kept;
}

static NSMutableDictionary *ReadDone(BOOL *repaired) {
    if (repaired) *repaired = NO;
    NSData *d = [NSData dataWithContentsOfFile:DonePath()];
    id root = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (repaired && d) *repaired = YES;
        return [NSMutableDictionary dictionary];
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id key in root) {
        NSDictionary *entry = [key isKindOfClass:[NSString class]]
            ? DoneEntry(root[key]) : nil;
        if (entry) out[key] = entry;
        else if (repaired) *repaired = YES;
    }
    return out;
}

static void WriteDone(NSDictionary *map) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:map
                                                options:NSJSONWritingPrettyPrinted
                                                  error:NULL];
    if (!d) return;
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[DonePath() stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    [d writeToFile:DonePath() atomically:YES];
}

NSDictionary *LoadDone(void) {
    BOOL repaired = NO;
    NSDictionary *map = ReadDone(&repaired);
    NSDictionary *kept = PruneDone(map, [NSDate date]);
    if (repaired || kept.count != map.count) WriteDone(kept);
    return kept;
}

NSArray *DoneEntries(void) {
    NSDictionary *map = LoadDone();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in map) {
        NSDictionary *e = map[key];
        [out addObject:@{ @"key": key,
                          @"name": e[@"name"] ?: @"",
                          @"due": e[@"due"] ?: @"" }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = [a[@"due"] compare:b[@"due"]];
        return r == NSOrderedSame ? [a[@"name"] compare:b[@"name"]] : r;
    }];
    return out;
}

void SetDone(NSDictionary *item, BOOL done) {
    NSMutableDictionary *map = ReadDone(NULL);
    NSString *key = DoneKey(item);
    if (done) {
        id due = item[@"due"], name = item[@"name"];
        map[key] = @{ @"due": [due isKindOfClass:[NSString class]] ? due : @"",
                      @"name": [name isKindOfClass:[NSString class]] ? name : @"" };
    } else {
        [map removeObjectForKey:key];
    }
    WriteDone(map);
}

void RestoreDone(NSArray *keys) {
    NSMutableDictionary *map = ReadDone(NULL);
    [map removeObjectsForKeys:keys];
    WriteDone(map);
}

NSString *TasksPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/tasks.json"];
}

static void WriteTasks(NSArray *tasks) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{ @"tasks": tasks }
                                                options:NSJSONWritingPrettyPrinted
                                                  error:NULL];
    if (!d) return;
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[TasksPath() stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    [d writeToFile:TasksPath() atomically:YES];
}

NSArray *PruneTasks(NSArray *tasks, NSDate *now) {
    NSMutableArray *kept = [NSMutableArray array];
    for (id t in tasks) {
        if (![t isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = StringField(t, @"name");
        NSString *due = StringField(t, @"due");
        if (!name.length) continue;
        NSDate *when = ParseISO(due);
        if (when && [when compare:now] == NSOrderedAscending) continue;
        [kept addObject:@{ @"name": name, @"due": due, @"task": @YES }];
    }
    return kept;
}

NSArray *LoadTasks(void) {
    NSData *d = [NSData dataWithContentsOfFile:TasksPath()];
    id root = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    NSArray *raw = [root isKindOfClass:[NSDictionary class]] ? root[@"tasks"] : nil;
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSArray *kept = PruneTasks(raw, [NSDate date]);
    if (kept.count != raw.count) WriteTasks(kept);
    return kept;
}

void AddTask(NSString *name, NSDate *due) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    NSMutableArray *tasks = [LoadTasks() mutableCopy];
    [tasks addObject:@{ @"name": trimmed,
                        @"due": [ISOFormatter() stringFromDate:due],
                        @"task": @YES }];
    WriteTasks(tasks);
}
