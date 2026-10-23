#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Test-only native factory boundary; never linked into the shipped bundle.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *TLConstructDetail(Class detailClass, BOOL preferLegacy);
NS_ASSUME_NONNULL_END
