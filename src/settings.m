#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "settings.h"
#import "views.h"
#import "ics.h"
#import "schedule.h"
#import "store.h"

static const CGFloat kLabelColumnWidth = 150.0;

static NSDate *DateFromYMD(int ymd) {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = ymd / 10000;
    c.month = (ymd / 100) % 100;
    c.day = ymd % 100;
    if (c.year < 1970 || c.month < 1 || c.month > 12) return [NSDate date];
    return [[NSCalendar currentCalendar] dateFromComponents:c] ?: [NSDate date];
}

@implementation SettingsWindow

- (instancetype)init {
    self = [super init];
    if (self) {
        self.classes = [NSMutableArray array];
        self.pendingRestores = [NSMutableSet set];
        [self buildWindow];
    }
    return self;
}

- (NSTextField *)labelWithText:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.alignment = NSTextAlignmentRight;
    return f;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    return b;
}

- (NSTableColumn *)columnWithId:(NSString *)ident title:(NSString *)title
                          width:(CGFloat)width {
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:ident];
    c.title = title;
    c.width = width;
    c.minWidth = 40;
    return c;
}

- (NSTextField *)sectionHeading:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    return f;
}

- (NSTextField *)hintWithText:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:11];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

- (NSView *)infoTip:(NSString *)tip {
    InfoTipView *v = [[InfoTipView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
    v.tip = tip;
    [v.widthAnchor constraintEqualToConstant:16].active = YES;
    [v.heightAnchor constraintEqualToConstant:16].active = YES;
    return v;
}

- (NSView *)centeredCell:(NSTextField *)field {
    NSView *box = [[NSView alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:2],
        [field.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-2],
        [field.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    return box;
}

- (NSGridView *)formWithRows:(NSArray *)rows fill:(NSIndexSet *)fillRows {
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 10;
    grid.columnSpacing = 10;
    [grid columnAtIndex:0].width = kLabelColumnWidth;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    for (NSInteger i = 0; i < grid.numberOfRows; i++) {
        [grid rowAtIndex:i].rowAlignment = NSGridRowAlignmentFirstBaseline;
        if ([fillRows containsIndex:(NSUInteger)i])
            [grid cellAtColumnIndex:1 rowIndex:i].xPlacement = NSGridCellPlacementFill;
    }
    return grid;
}

- (NSStackView *)sectionWithHeading:(NSString *)heading body:(NSView *)body {
    NSStackView *v = [NSStackView stackViewWithViews:@[
        [self sectionHeading:heading], body]];
    v.orientation = NSUserInterfaceLayoutOrientationVertical;
    v.alignment = NSLayoutAttributeLeading;
    v.spacing = 8;
    return v;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 960, 700)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"classbar settings";
    self.window.releasedWhenClosed = NO;
    self.window.minSize = NSMakeSize(820, 560);
    self.window.delegate = self;
    [self.window center];

    self.feedField = [NSTextField textFieldWithString:@""];
    self.feedField.placeholderString =
        @"https://school.instructure.com/feeds/calendars/user_….ics";
    self.homeField = [NSTextField textFieldWithString:@""];
    self.homeField.placeholderString = @"https://school.instructure.com/";
    self.beforeField = [NSTextField textFieldWithString:@""];
    self.beforeField.placeholderString = @"classes begin sep 9";

    self.startPicker = [[NSDatePicker alloc] init];
    self.startPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.startPicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.endPicker = [[NSDatePicker alloc] init];
    self.endPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.endPicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    for (NSDatePicker *picker in @[self.startPicker, self.endPicker]) {
        [picker.widthAnchor constraintGreaterThanOrEqualToConstant:118].active = YES;
        [picker setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                         forOrientation:
            NSLayoutConstraintOrientationHorizontal];
    }

    self.capField = [NSTextField textFieldWithString:@""];
    self.capField.alignment = NSTextAlignmentRight;
    self.capField.target = self;
    self.capField.action = @selector(capFieldEdited);
    [self.capField.widthAnchor constraintEqualToConstant:52].active = YES;

    self.capStepper = [[NSStepper alloc] init];
    self.capStepper.minValue = kMinAssignmentCap;
    self.capStepper.maxValue = kMaxAssignmentCap;
    self.capStepper.increment = 1;
    self.capStepper.valueWraps = NO;
    self.capStepper.target = self;
    self.capStepper.action = @selector(capStepperMoved);

    self.donePopup = [[NSPopUpButton alloc] init];
    [self.donePopup addItemsWithTitles:@[@"keep at the bottom",
                                         @"hide from the menu"]];
    [self.donePopup setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.feedStatus = [self hintWithText:@""];
    [self.feedStatus.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;

    NSStackView *feedRow = [NSStackView stackViewWithViews:@[
        self.feedField,
        [self infoTip:@"canvas → calendar → calendar feed"],
        [self buttonWithTitle:@"test" action:@selector(refresh)],
        self.feedStatus]];
    feedRow.spacing = 8;
    [self.feedField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                               forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *termRow = [NSStackView stackViewWithViews:@[
        self.startPicker, [self hintWithText:@"through"], self.endPicker]];
    termRow.spacing = 10;

    NSStackView *capRow = [NSStackView stackViewWithViews:@[
        self.capField, self.capStepper,
        [self hintWithText:@"including completed work"]]];
    capRow.spacing = 6;

    NSStackView *doneCol = [NSStackView stackViewWithViews:@[
        self.donePopup,
        [self buttonWithTitle:@"restore…" action:@selector(openDoneSheet)]]];
    doneCol.spacing = 8;

    NSGridView *canvasForm = [self formWithRows:@[
        @[[self labelWithText:@"calendar feed"], feedRow],
        @[[self labelWithText:@"site"], self.homeField],
    ] fill:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];

    NSGridView *termForm = [self formWithRows:@[
        @[[self labelWithText:@"dates"], termRow],
        @[[self labelWithText:@"message before it starts"], self.beforeField],
    ] fill:[NSIndexSet indexSetWithIndex:1]];

    NSGridView *menuForm = [self formWithRows:@[
        @[[self labelWithText:@"assignment rows"], capRow],
        @[[self labelWithText:@"completed work"], doneCol],
    ] fill:[NSIndexSet indexSet]];

    self.table = [[NSTableView alloc] init];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.allowsMultipleSelection = YES;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.table.rowHeight = 22;
    for (NSArray *spec in @[ @[@"name", @"name", @150], @[@"code", @"code", @82],
                             @[@"room", @"room", @134], @[@"days", @"days", @134],
                             @[@"start", @"start", @54], @[@"end", @"end", @54],
                             @[@"canvas", @"canvas link", @150],
                             @[@"zoom", @"zoom link", @130] ])
        [self.table addTableColumn:[self columnWithId:spec[0] title:spec[1]
                                                width:[spec[2] doubleValue]]];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSBezelBorder;

    NSView *classSpacer = [[NSView alloc] init];
    [classSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *classButtons = [NSStackView stackViewWithViews:@[
        [self buttonWithTitle:@"add" action:@selector(addClass)],
        [self buttonWithTitle:@"remove" action:@selector(removeSelected)],
        [self infoTip:@"days takes MWF, TuTh, Mon Wed, or M W F"],
        classSpacer,
        [self buttonWithTitle:@"import from .ics…" action:@selector(importICS)],
    ]];
    classButtons.spacing = 8;

    NSStackView *classBody = [NSStackView stackViewWithViews:@[scroll, classButtons]];
    classBody.orientation = NSUserInterfaceLayoutOrientationVertical;
    classBody.alignment = NSLayoutAttributeLeading;
    classBody.spacing = 8;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.font = [NSFont systemFontOfSize:11];

    NSView *footSpacer = [[NSView alloc] init];
    [footSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *save = [self buttonWithTitle:@"save" action:@selector(save)];
    save.keyEquivalent = @"\r";
    NSButton *revert = [self buttonWithTitle:@"revert" action:@selector(load)];

    NSStackView *footer = [NSStackView stackViewWithViews:@[
        self.statusLabel, footSpacer, revert, save]];
    footer.spacing = 8;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        [self sectionWithHeading:@"canvas" body:canvasForm],
        [self sectionWithHeading:@"term" body:termForm],
        [self sectionWithHeading:@"menu" body:menuForm],
        [self sectionWithHeading:@"classes" body:classBody],
        footer,
    ]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 20;
    root.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [root setHuggingPriority:NSLayoutPriorityDefaultHigh
              forOrientation:NSLayoutConstraintOrientationVertical];

    NSView *content = self.window.contentView;
    [content addSubview:root];
    NSMutableArray *rules = [NSMutableArray arrayWithArray:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:190],
    ]];
    for (NSView *v in @[canvasForm, termForm, menuForm, classBody, footer,
                        scroll, classButtons])
        [rules addObject:[v.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                       constant:-40]];
    for (NSView *v in root.arrangedSubviews)
        [rules addObject:[v.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                       constant:-40]];
    [NSLayoutConstraint activateConstraints:rules];
}


- (void)show {
    [self load];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)setStatus:(NSString *)text {
    self.feedStatus.stringValue = text ?: @"";
}

- (void)setNote:(NSString *)text {
    self.statusLabel.stringValue = text ?: @"";
}

- (void)setCap:(int)cap {
    int clamped = ClampCap(cap);
    self.capField.stringValue = [NSString stringWithFormat:@"%d", clamped];
    self.capStepper.integerValue = clamped;
}

- (void)capFieldEdited {
    [self setCap:self.capField.intValue];
}

- (void)capStepperMoved {
    [self setCap:(int)self.capStepper.integerValue];
}

- (void)load {
    NSData *d = [NSData dataWithContentsOfFile:SchedulePath()];
    id root = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) root = @{};

    self.feedField.stringValue = [root[@"canvasFeed"] isKindOfClass:[NSString class]]
        ? root[@"canvasFeed"] : @"";
    self.homeField.stringValue = [root[@"canvasHome"] isKindOfClass:[NSString class]]
        ? root[@"canvasHome"] : @"";
    [self setCap:[root[@"assignmentCap"] isKindOfClass:[NSNumber class]]
        ? [root[@"assignmentCap"] intValue] : kDefaultAssignmentCap];
    [self.donePopup selectItemAtIndex:[root[@"hideDone"] boolValue] ? 1 : 0];

    NSDictionary *term = [root[@"term"] isKindOfClass:[NSDictionary class]]
        ? root[@"term"] : @{};
    self.startPicker.dateValue = DateFromYMD([term[@"start"] intValue]);
    self.endPicker.dateValue = DateFromYMD([term[@"end"] intValue]);
    self.beforeField.stringValue = [term[@"beforeLabel"] isKindOfClass:[NSString class]]
        ? term[@"beforeLabel"] : @"";

    [self.classes removeAllObjects];
    for (NSDictionary *c in root[@"classes"]) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        NSMutableArray *days = [NSMutableArray array];
        for (NSNumber *n in c[@"days"])
            if ([n isKindOfClass:[NSNumber class]]) [days addObject:n];
        [self.classes addObject:[@{
            @"name": c[@"name"] ?: @"", @"code": c[@"code"] ?: @"",
            @"room": c[@"room"] ?: @"", @"days": days,
            @"start": c[@"start"] ?: @"", @"end": c[@"end"] ?: @"",
            @"canvas": c[@"canvas"] ?: @"", @"zoom": c[@"zoom"] ?: @"",
        } mutableCopy]];
    }
    [self.pendingRestores removeAllObjects];
    [self.table reloadData];
    [self.table sizeLastColumnToFit];
    [self setStatus:@""];
    [self setNote:@""];
    self.savedSnapshot = [self buildRoot];
}

- (BOOL)hasUnsavedChanges {
    [self.window makeFirstResponder:nil];
    if (self.pendingRestores.count) return YES;
    if (!self.savedSnapshot) return NO;
    return ![[self buildRoot] isEqualToDictionary:self.savedSnapshot];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender != self.window || ![self hasUnsavedChanges]) return YES;

    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = @"save your changes?";
    ask.informativeText = @"closing without saving discards them.";
    [ask addButtonWithTitle:@"save"];
    [ask addButtonWithTitle:@"cancel"];
    [ask addButtonWithTitle:@"discard"];
    ask.buttons[2].keyEquivalent = @"d";
    ask.buttons[2].keyEquivalentModifierMask = NSEventModifierFlagCommand;

    NSModalResponse answer = [ask runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) { [self load]; return YES; }
    return [self writeSettings];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == self.doneTable) return (NSInteger)self.doneRows.count;
    return (NSInteger)self.classes.count;
}

- (NSTextField *)fieldInside:(NSView *)box {
    return (NSTextField *)box.subviews.firstObject;
}

- (NSView *)cellFor:(NSTableView *)tv key:(NSString *)key editable:(BOOL)editable {
    NSView *box = [tv makeViewWithIdentifier:key owner:self];
    if (box) return box;

    NSTextField *field = editable ? [NSTextField textFieldWithString:@""]
                                  : [NSTextField labelWithString:@""];
    field.font = [NSFont systemFontOfSize:12];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    if (editable) {
        field.bordered = NO;
        field.drawsBackground = NO;
        field.target = self;
        field.action = @selector(cellEdited:);
    }
    box = [self centeredCell:field];
    box.identifier = key;
    return box;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)column
                  row:(NSInteger)row {
    NSString *key = column.identifier;

    if (tv == self.doneTable) {
        NSView *box = [self cellFor:tv key:key editable:NO];
        NSTextField *cell = [self fieldInside:box];
        NSDictionary *entry = self.doneRows[(NSUInteger)row];
        if ([key isEqualToString:@"doneDue"]) {
            NSDate *due = ParseISO(entry[@"due"]);
            cell.stringValue = due ? DueLabel([NSCalendar currentCalendar], due) : @"";
        } else {
            cell.stringValue = [entry[@"name"] length] ? entry[@"name"] : entry[@"key"];
        }
        return box;
    }

    NSView *box = [self cellFor:tv key:key editable:YES];
    NSTextField *field = [self fieldInside:box];
    NSDictionary *c = self.classes[(NSUInteger)row];
    field.stringValue = [key isEqualToString:@"days"] ? DaysToText(c[@"days"])
                                                      : (c[key] ?: @"");
    return box;
}

- (void)cellEdited:(NSTextField *)sender {
    NSInteger row = [self.table rowForView:sender];
    if (row < 0 || row >= (NSInteger)self.classes.count) return;
    NSMutableDictionary *c = self.classes[(NSUInteger)row];
    NSString *key = sender.identifier;
    if ([key isEqualToString:@"days"]) {
        NSArray *days = TextToDays(sender.stringValue);
        c[@"days"] = [days mutableCopy];
        sender.stringValue = DaysToText(days);
    } else {
        c[key] = sender.stringValue;
    }
}

- (void)addClass {
    [self.classes addObject:[@{ @"name": @"new class", @"code": @"", @"room": @"",
                                @"days": [NSMutableArray array],
                                @"start": @"09:00", @"end": @"10:00",
                                @"canvas": @"", @"zoom": @"" } mutableCopy]];
    [self.table reloadData];
    NSInteger row = (NSInteger)self.classes.count - 1;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
            byExtendingSelection:NO];
    [self.table scrollRowToVisible:row];
}

- (void)removeSelected {
    NSIndexSet *rows = self.table.selectedRowIndexes;
    if (!rows.count) return;
    [self.classes removeObjectsAtIndexes:rows];
    [self.table reloadData];
}

- (void)importICS {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    UTType *ics = [UTType typeWithFilenameExtension:@"ics"];
    if (ics) panel.allowedContentTypes = @[ics];
    panel.allowsMultipleSelection = NO;
    panel.message = @"choose a calendar export that contains your class meetings.";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;

    NSString *text = [NSString stringWithContentsOfURL:panel.URL
                                              encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *result = text ? cb_ics_classes(text) : nil;
    if (!result) {
        [self alert:@"nothing to import"
               info:@"no weekly class meetings were found in that calendar."];
        return;
    }
    [self applyImport:result];
}

- (void)applyImport:(NSDictionary *)result {
    NSMutableDictionary *previous = [NSMutableDictionary dictionary];
    for (NSMutableDictionary *c in self.classes) {
        NSString *key = [c[@"code"] length] ? c[@"code"] : c[@"name"];
        NSMutableArray *list = previous[key];
        if (!list) { list = [NSMutableArray array]; previous[key] = list; }
        [list addObject:c];
    }

    NSMutableArray *merged = [NSMutableArray array];
    for (NSDictionary *c in result[@"classes"]) {
        NSString *key = [c[@"code"] length] ? c[@"code"] : c[@"name"];
        NSMutableArray *list = previous[key];
        NSMutableDictionary *old = list.count ? list[0] : nil;
        if (old) [list removeObjectAtIndex:0];
        NSMutableDictionary *entry = [c mutableCopy];
        entry[@"canvas"] = old[@"canvas"] ?: @"";
        entry[@"zoom"] = old[@"zoom"] ?: @"";
        if ([old[@"name"] length]) entry[@"name"] = old[@"name"];
        [merged addObject:entry];
    }

    self.classes = merged;
    NSDictionary *term = result[@"term"];
    self.startPicker.dateValue = DateFromYMD([term[@"start"] intValue]);
    self.endPicker.dateValue = DateFromYMD([term[@"end"] intValue]);
    if (!self.beforeField.stringValue.length)
        self.beforeField.stringValue = term[@"beforeLabel"] ?: @"";
    [self.table reloadData];
    [self setNote:[NSString stringWithFormat:@"imported %lu classes, not saved yet",
                   (unsigned long)merged.count]];
}

- (void)reloadDoneRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *e in DoneEntries())
        if (![self.pendingRestores containsObject:e[@"key"]]) [rows addObject:e];
    self.doneRows = rows;
}

- (void)openDoneSheet {
    if (!self.pendingRestores) self.pendingRestores = [NSMutableSet set];
    [self reloadDoneRows];

    if (!self.doneSheet) {
        self.doneSheet = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 460, 320)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        self.doneSheet.title = @"completed assignments";

        self.doneTable = [[NSTableView alloc] init];
        self.doneTable.dataSource = self;
        self.doneTable.delegate = self;
        self.doneTable.allowsMultipleSelection = YES;
        self.doneTable.usesAlternatingRowBackgroundColors = YES;
        self.doneTable.columnAutoresizingStyle =
            NSTableViewLastColumnOnlyAutoresizingStyle;
        self.doneTable.rowHeight = 22;
        [self.doneTable addTableColumn:[self columnWithId:@"doneDue"
                                                    title:@"due" width:110]];
        [self.doneTable addTableColumn:[self columnWithId:@"doneName"
                                                    title:@"assignment" width:300]];

        NSScrollView *scroll = [[NSScrollView alloc] init];
        scroll.documentView = self.doneTable;
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;

        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSButton *close = [self buttonWithTitle:@"done" action:@selector(closeDoneSheet)];
        close.keyEquivalent = @"\r";

        NSStackView *buttons = [NSStackView stackViewWithViews:@[
            [self buttonWithTitle:@"restore selected" action:@selector(restoreSelected)],
            [self buttonWithTitle:@"restore all" action:@selector(restoreAll)],
            spacer,
            [self hintWithText:@"applied when you press save"],
            close]];
        buttons.spacing = 8;

        NSStackView *root = [NSStackView stackViewWithViews:@[scroll, buttons]];
        root.orientation = NSUserInterfaceLayoutOrientationVertical;
        root.alignment = NSLayoutAttributeLeading;
        root.spacing = 12;
        root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
        root.translatesAutoresizingMaskIntoConstraints = NO;

        NSView *content = self.doneSheet.contentView;
        [content addSubview:root];
        [NSLayoutConstraint activateConstraints:@[
            [root.topAnchor constraintEqualToAnchor:content.topAnchor],
            [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
            [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [scroll.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
            [buttons.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
        ]];
    }

    [self.doneTable reloadData];
    [self.doneTable sizeLastColumnToFit];
    [self.window beginSheet:self.doneSheet completionHandler:nil];
}

- (void)closeDoneSheet {
    [self.window endSheet:self.doneSheet];
}

- (void)restoreKeys:(NSArray *)keys {
    if (!keys.count) return;
    [self.pendingRestores addObjectsFromArray:keys];
    [self reloadDoneRows];
    [self.doneTable reloadData];
    [self setNote:[NSString stringWithFormat:@"%lu to restore on Save",
                   (unsigned long)self.pendingRestores.count]];
}

- (void)restoreSelected {
    NSMutableArray *keys = [NSMutableArray array];
    [self.doneTable.selectedRowIndexes enumerateIndexesUsingBlock:
        ^(NSUInteger i, BOOL *stop __unused) {
        if (i < self.doneRows.count) [keys addObject:self.doneRows[i][@"key"]];
    }];
    [self restoreKeys:keys];
}

- (void)restoreAll {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *r in self.doneRows) [keys addObject:r[@"key"]];
    [self restoreKeys:keys];
}

- (void)alert:(NSString *)title info:(NSString *)info {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = title;
    a.informativeText = info;
    [a beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)refresh {
    NSURL *url = FeedURL(self.feedField.stringValue);
    if (!url) {
        [self setStatus:self.feedField.stringValue.length ? @"not a url"
                                                          : @"no feed url yet"];
        return;
    }

    [self setStatus:@"testing…"];
    NSString *home = self.homeField.stringValue;
    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:20];
    __weak SettingsWindow *weak = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]]
                       ? [(NSHTTPURLResponse *)resp statusCode] : 200;
        NSString *body = (data && !err && code < 400)
            ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSUInteger found = body ? cb_ics_items(body, home).count : 0;
        NSString *note;
        if (err) note = @"no reply";
        else if (code >= 400) note = [NSString stringWithFormat:@"canvas said %ld",
                                      (long)code];
        else if (!found) note = @"reached it, no assignments";
        else note = [NSString stringWithFormat:@"%lu assignments", (unsigned long)found];
        dispatch_async(dispatch_get_main_queue(), ^{ [weak setStatus:note]; });
    }] resume];
}

- (NSArray *)problems {
    NSMutableArray *problems = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.classes.count; i++) {
        NSDictionary *c = self.classes[i];
        NSString *label = [c[@"name"] length] ? c[@"name"]
                        : [NSString stringWithFormat:@"row %lu", (unsigned long)i + 1];
        if (![c[@"name"] length])
            [problems addObject:[NSString stringWithFormat:@"%@ has no name", label]];
        if (![c[@"days"] count])
            [problems addObject:[NSString stringWithFormat:@"%@ has no days", label]];
        if (ParseClock(c[@"start"]) < 0 || ParseClock(c[@"end"]) < 0)
            [problems addObject:[NSString stringWithFormat:
                @"%@ needs times as HH:MM, 24 hour", label]];
    }
    return problems;
}

- (NSDictionary *)buildRoot {
    NSMutableArray *classes = [NSMutableArray array];
    for (NSDictionary *c in self.classes) {
        NSMutableDictionary *entry = [@{ @"name": c[@"name"], @"code": c[@"code"] ?: @"",
                                         @"room": c[@"room"] ?: @"", @"days": c[@"days"],
                                         @"start": c[@"start"], @"end": c[@"end"] } mutableCopy];
        if ([c[@"canvas"] length]) entry[@"canvas"] = c[@"canvas"];
        if ([c[@"zoom"] length]) entry[@"zoom"] = c[@"zoom"];
        [classes addObject:entry];
    }

    return @{
        @"canvasHome": self.homeField.stringValue,
        @"canvasFeed": self.feedField.stringValue,
        @"assignmentCap": @(ClampCap(self.capField.intValue)),
        @"hideDone": @(self.donePopup.indexOfSelectedItem == 1),
        @"term": @{ @"start": @(YMD(self.startPicker.dateValue)),
                    @"end": @(YMD(self.endPicker.dateValue)),
                    @"beforeLabel": self.beforeField.stringValue },
        @"classes": classes,
    };
}

- (void)save {
    [self writeSettings];
}

- (BOOL)writeSettings {
    [self.window makeFirstResponder:nil];

    NSArray *problems = [self problems];
    if (problems.count) {
        [self alert:@"fix these first" info:[problems componentsJoinedByString:@"\n"]];
        return NO;
    }

    NSDictionary *root = [self buildRoot];
    NSData *json = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    [[NSFileManager defaultManager]
             createDirectoryAtPath:[SchedulePath() stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!json || ![json writeToFile:SchedulePath() atomically:YES]) {
        [self alert:@"could not save" info:SchedulePath()];
        return NO;
    }

    if (self.pendingRestores.count) {
        RestoreDone([self.pendingRestores allObjects]);
        [self.pendingRestores removeAllObjects];
    }

    self.savedSnapshot = root;
    [self setNote:@"saved"];
    if (self.target && self.savedAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.savedAction);
    return YES;
}

@end
