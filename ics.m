#import <Cocoa/Cocoa.h>
#import "ics.h"
#import "schedule.h"
#import "store.h"

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

NSDate *IcsDate(NSString *tzid, NSString *value) {
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

static BOOL IcsDateOnly(NSArray *parts, NSString *value) {
    for (NSUInteger i = 1; i < parts.count; i++)
        if ([[parts[i] uppercaseString] isEqualToString:@"VALUE=DATE"]) return YES;
    return value.length == 8;
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

NSString *FirstGroup(NSString *text, NSString *pattern) {
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
            NSString *raw = [value stringByTrimmingCharactersInSet:ws];
            NSDate *d = IcsDate(tzid, raw);
            if (d) {
                event[name] = d;
                if (IcsDateOnly(parts, raw))
                    event[[name stringByAppendingString:@"-DATEONLY"]] = @YES;
            }
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

NSArray *cb_ics_items(NSString *text, NSString *canvasHome) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *e in IcsEvents(text)) {
        NSString *summary = e[@"SUMMARY"];
        NSString *key = e[@"DTSTART"] ? @"DTSTART" : @"DTEND";
        NSDate *due = e[key];
        if (!summary.length || !due) continue;
        if ([e[[key stringByAppendingString:@"-DATEONLY"]] boolValue]) {
            if ([key isEqualToString:@"DTEND"]) {
                NSDateComponents *back = [[NSDateComponents alloc] init];
                back.day = -1;
                due = [[NSCalendar currentCalendar] dateByAddingComponents:back
                                                                    toDate:due
                                                                   options:0] ?: due;
            }
            due = EndOfDay(due);
        }

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

NSArray *cb_ics_window(NSArray *items, NSDate *now, int backDays,
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

void SplitCourseTitle(NSString *summary, NSString **name, NSString **code) {
    *name = summary;
    *code = @"";
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"\\b([A-Z]{2,5})[\\s\\-_]?([0-9]{3,4}[A-Z]?)\\b"
                             options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:summary options:0
                                               range:NSMakeRange(0, summary.length)];
    if (!m) return;
    *code = [NSString stringWithFormat:@"%@ %@",
             [summary substringWithRange:[m rangeAtIndex:1]],
             [summary substringWithRange:[m rangeAtIndex:2]]];
    NSString *stripped = [summary stringByReplacingCharactersInRange:m.range withString:@" "];
    while ([stripped rangeOfString:@"  "].location != NSNotFound)
        stripped = [stripped stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    stripped = [stripped stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@" -–—,:;()[]\t\n"]];
    if (stripped.length) *name = stripped;
}

NSString *ClockText(NSDate *date) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"HH:mm";
    return [f stringFromDate:date];
}

int YMD(NSDate *date) {
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
          fromDate:date];
    return (int)c.year * 10000 + (int)c.month * 100 + (int)c.day;
}

int WeekdayIndex(NSDate *date) {
    NSInteger w = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday
                                                 fromDate:date];
    NSInteger i = w - 2;
    return (int)(i < 0 ? 6 : i);
}

NSDictionary *cb_ics_classes(NSString *text) {
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];

    for (NSDictionary *e in IcsEvents(text)) {
        NSDate *start = e[@"DTSTART"];
        NSDate *end = e[@"DTEND"];
        NSString *summary = e[@"SUMMARY"];
        if (!start || !end || !summary.length) continue;

        NSString *rrule = e[@"RRULE"] ?: @"";
        NSMutableArray *days = [NSMutableArray array];
        NSDate *last = start;
        if (rrule.length) {
            if ([rrule containsString:@"FREQ="] && ![rrule containsString:@"FREQ=WEEKLY"])
                continue;
            NSString *byday = FirstGroup(rrule, @"BYDAY=([A-Z,]+)");
            for (NSString *token in [byday componentsSeparatedByString:@","]) {
                if (token.length < 2) continue;
                NSArray *days2 = TextToDays([token substringFromIndex:token.length - 2]);
                for (NSNumber *d in days2) if (![days containsObject:d]) [days addObject:d];
            }
            NSString *until = FirstGroup(rrule, @"UNTIL=([0-9]{8})");
            NSDate *untilDate = until ? IcsDate(nil, until) : nil;
            if (untilDate) last = untilDate;
        }
        if (!days.count) [days addObject:@(WeekdayIndex(start))];

        NSString *name = nil, *code = nil;
        SplitCourseTitle(summary, &name, &code);
        NSString *room = e[@"LOCATION"] ?: @"";
        NSString *startText = ClockText(start);
        NSString *endText = ClockText(end);
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%@",
                         code.length ? code : name, startText, endText, room];

        NSMutableDictionary *g = groups[key];
        if (!g) {
            g = [@{ @"name": name, @"code": code, @"room": room,
                    @"days": [NSMutableArray arrayWithArray:days],
                    @"start": startText, @"end": endText,
                    @"first": start, @"last": last } mutableCopy];
            groups[key] = g;
            [order addObject:key];
            continue;
        }
        NSMutableArray *have = g[@"days"];
        for (NSNumber *d in days) if (![have containsObject:d]) [have addObject:d];
        if ([start compare:g[@"first"]] == NSOrderedAscending) g[@"first"] = start;
        if ([last compare:g[@"last"]] == NSOrderedDescending) g[@"last"] = last;
    }

    if (!order.count) return nil;

    NSMutableArray *classes = [NSMutableArray array];
    NSDate *first = nil, *last = nil;
    for (NSString *key in order) {
        NSMutableDictionary *g = groups[key];
        if (!first || [g[@"first"] compare:first] == NSOrderedAscending) first = g[@"first"];
        if (!last || [g[@"last"] compare:last] == NSOrderedDescending) last = g[@"last"];
        NSMutableArray *days = g[@"days"];
        [days sortUsingSelector:@selector(compare:)];
        [classes addObject:[@{ @"name": g[@"name"], @"code": g[@"code"],
                               @"room": g[@"room"], @"days": days,
                               @"start": g[@"start"], @"end": g[@"end"] } mutableCopy]];
    }
    [classes sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSNumber *da = [a[@"days"] firstObject], *db = [b[@"days"] firstObject];
        NSComparisonResult r = [da compare:db];
        return r == NSOrderedSame ? [a[@"start"] compare:b[@"start"]] : r;
    }];

    NSDateFormatter *label = [[NSDateFormatter alloc] init];
    label.dateFormat = @"MMM d";
    return @{ @"classes": classes,
              @"term": @{ @"start": @(YMD(first)), @"end": @(YMD(last)),
                          @"beforeLabel": [NSString stringWithFormat:@"Classes begin %@",
                                           [label stringFromDate:first]] } };
}
