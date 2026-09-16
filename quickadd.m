#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "quickadd.h"
#import "store.h"

@implementation TaskComposer

- (instancetype)init {
    self = [super init];
    if (self) [self build];
    return self;
}

- (NSTextField *)labelWithText:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:12];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.controlSize = NSControlSizeSmall;
    b.font = [NSFont systemFontOfSize:12];
    b.bezelColor = nil;
    return b;
}

- (NSDatePicker *)pickerWithElements:(NSDatePickerElementFlags)flags width:(CGFloat)w {
    NSDatePicker *p = [[NSDatePicker alloc] init];
    p.datePickerElements = flags;
    p.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    p.font = [NSFont systemFontOfSize:12];
    p.bordered = NO;
    p.drawsBackground = NO;
    p.focusRingType = NSFocusRingTypeNone;
    [p.widthAnchor constraintEqualToConstant:w].active = YES;
    return p;
}

- (void)build {
    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = @"New task";
    self.nameField.font = [NSFont systemFontOfSize:12];
    self.nameField.bordered = NO;
    self.nameField.drawsBackground = NO;
    self.nameField.focusRingType = NSFocusRingTypeNone;
    self.nameField.target = self;
    self.nameField.action = @selector(add);

    self.dayPicker = [self pickerWithElements:NSDatePickerElementFlagYearMonthDay
                                        width:104];
    self.timePicker = [self pickerWithElements:NSDatePickerElementFlagHourMinute
                                         width:78];

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *add = [self buttonWithTitle:@"Add" action:@selector(add)];
    add.keyEquivalent = @"\r";

    NSStackView *dueRow = [NSStackView stackViewWithViews:@[
        [self labelWithText:@"Due"], self.dayPicker, self.timePicker, spacer]];
    dueRow.spacing = 8;

    NSView *buttonSpacer = [[NSView alloc] init];
    [buttonSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[
        buttonSpacer,
        [self buttonWithTitle:@"Cancel" action:@selector(cancel)], add]];
    buttons.spacing = 8;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        self.nameField, dueRow, buttons]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    self.backdrop = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, 320, 112)];
    self.backdrop.material = NSVisualEffectMaterialMenu;
    self.backdrop.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.backdrop.state = NSVisualEffectStateActive;
    [self.backdrop addSubview:root];

    self.widthRule = [self.backdrop.widthAnchor constraintEqualToConstant:320];
    [NSLayoutConstraint activateConstraints:@[
        self.widthRule,
        [root.topAnchor constraintEqualToAnchor:self.backdrop.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:self.backdrop.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:self.backdrop.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:self.backdrop.trailingAnchor],
        [self.nameField.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                   constant:-28],
        [dueRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-28],
        [buttons.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-28],
    ]];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = self.backdrop;

    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = vc;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = NO;
    self.popover.delegate = self;
}

- (void)showRelativeTo:(NSView *)anchor width:(CGFloat)width {
    self.widthRule.constant = MAX(280.0, width);
    [self.backdrop layoutSubtreeIfNeeded];
    CGFloat height = self.backdrop.fittingSize.height;
    if (height < 60) height = 112;
    self.popover.contentSize = NSMakeSize(self.widthRule.constant, height);

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *parts = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                               NSCalendarUnitDay)
                                     fromDate:[NSDate date]];
    parts.hour = 23;
    parts.minute = 59;
    NSDate *tonight = [cal dateFromComponents:parts] ?: [NSDate date];

    self.nameField.stringValue = @"";
    self.dayPicker.dateValue = tonight;
    self.timePicker.dateValue = tonight;

    if (!anchor) return;

    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:anchor.bounds ofView:anchor
                       preferredEdge:NSRectEdgeMaxY];
    [self.popover.contentViewController.view.window
        makeFirstResponder:self.nameField];
}

- (void)cancel {
    [self.popover performClose:nil];
}

- (NSDate *)chosenDue {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *day = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                             NSCalendarUnitDay)
                                   fromDate:self.dayPicker.dateValue];
    NSDateComponents *clock = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                     fromDate:self.timePicker.dateValue];
    day.hour = clock.hour;
    day.minute = clock.minute;
    day.second = 0;
    return [cal dateFromComponents:day] ?: self.dayPicker.dateValue;
}

- (void)add {
    if (self.adding) return;

    NSString *name = self.nameField.stringValue;
    if (![name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]].length) {
        NSBeep();
        return;
    }

    self.adding = YES;
    AddTask(name, [self chosenDue]);
    self.nameField.stringValue = @"";
    [self.popover performClose:nil];
    self.adding = NO;

    if (self.target && self.addedAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.addedAction);
}

@end
