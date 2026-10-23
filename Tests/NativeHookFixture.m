#import "NativeHookFixture.h"

static NSUInteger installations = 0;

void MSHookMessageEx(Class target, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(target, selector);
    *original = method_setImplementation(method, replacement);
    installations += 1;
}

NSUInteger TLHookInstallCount(void) {
    return installations;
}
