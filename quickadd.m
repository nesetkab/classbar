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
    f.alignment = NSTextAlignmentRight;
    f.font = [NSFont systemFontOfSize:12];
    f.textColor = [NSColor secondaryLabelColor];
    [f.widthAnchor constraintEqualToConstant:34].active = YES;
    return f;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.controlSize = NSControlSizeSmall;
    b.font = [NSFont systemFontOfSize:12];
    return b;
}

- (NSDatePicker *)pickerWithElements:(NSDatePickerElementFlags)flags width:(CGFloat)w {
    NSDatePicker *p = [[NSDatePicker alloc] init];
    p.datePickerElements = flags;
    p.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    p.font = [NSFont systemFontOfSize:12];
    [p.widthAnchor constraintEqualToConstant:w].active = YES;
    return p;
}

- (void)build {
    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = @"What do you need to do?";
    self.nameField.font = [NSFont systemFontOfSize:13];
    self.nameField.target = self;
    self.nameField.action = @selector(add);

    self.dayPicker = [self pickerWithElements:NSDatePickerElementFlagYearMonthDay
                                        width:112];
    self.timePicker = [self pickerWithElements:NSDatePickerElementFlagHourMinute
                                         width:86];

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
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 14, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 330, 132)];
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.nameField.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                   constant:-32],
        [dueRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
        [buttons.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-32],
    ]];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = content;

    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = vc;
    self.popover.contentSize = NSMakeSize(330, 132);
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = YES;
    self.popover.delegate = self;
}

- (void)showRelativeTo:(NSView *)anchor {
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
