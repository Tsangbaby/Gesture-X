#import <Foundation/Foundation.h>
#import "../Interfaces/TapLockNativeRuntime/NativeRuntime.h"

// Test-only method-replacement seam, not the handset's Hook backend.
NSUInteger TLHookInstallCount(void);
