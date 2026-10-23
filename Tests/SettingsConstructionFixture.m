#import "SettingsConstructionFixture.h"

// A native UIKit test double, not the device Preferences.framework.
// In particular, the superclass chain MUST NOT implement initForContentSize:.
@interface PSViewController : UIViewController
@end
@implementation PSViewController
@end

// Declaration for the test factory's message; deliberately no implementation.
@interface NSObject (TapLockLegacyConstructorDeclaration)
- (instancetype)initForContentSize:(CGSize)size;
@end

NSDictionary<NSString *, id> *TLConstructDetail(Class detailClass, BOOL preferLegacy) {
    @try {
        id allocated = [detailClass alloc];
        BOOL legacy = preferLegacy && [allocated respondsToSelector:@selector(initForContentSize:)];
        id controller = legacy ? [allocated initForContentSize:CGSizeMake(390, 844)] : [allocated init];
        return @{@"controller": controller, @"path": legacy ? @"legacy" : @"default"};
    } @catch (NSException *exception) {
        return @{@"exception": exception.name, @"reason": exception.reason ?: @""};
    }
}
