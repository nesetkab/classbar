#import <Cocoa/Cocoa.h>

@interface SettingsWindow : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSMutableArray *classes;
@property (strong) NSTextField *feedField;
@property (strong) NSTextField *homeField;
@property (strong) NSDatePicker *startPicker;
@property (strong) NSDatePicker *endPicker;
@property (strong) NSTextField *beforeField;
@property (strong) NSTextField *capField;
@property (strong) NSStepper *capStepper;
@property (strong) NSPopUpButton *donePopup;
@property (strong) NSWindow *doneSheet;
@property (strong) NSTableView *doneTable;
@property (strong) NSMutableArray *doneRows;
@property (strong) NSMutableSet *pendingRestores;
@property (strong) NSTableView *table;
@property (strong) NSTextField *statusLabel;
@property (strong) NSTextField *feedStatus;
@property (weak)   id target;
@property (assign) SEL savedAction;
@property (assign) SEL refreshAction;
- (void)show;
- (void)load;
- (void)setStatus:(NSString *)text;
- (void)setNote:(NSString *)text;
- (void)setCap:(int)cap;
- (NSArray *)problems;
- (NSDictionary *)buildRoot;
- (void)openDoneSheet;
- (void)closeDoneSheet;
- (void)restoreAll;
@end
