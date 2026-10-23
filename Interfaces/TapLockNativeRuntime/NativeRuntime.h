#import <objc/runtime.h>

// Declaration only. The jailbreak's substrate-compatible backend implements it.
// ABI: https://www.cydiasubstrate.com/api/c/MSHookMessageEx/
void MSHookMessageEx(Class _Nonnull target, SEL _Nonnull selector,
                     IMP _Nonnull replacement, IMP _Nullable * _Nullable original);
