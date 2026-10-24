// macOS test dylib only. No system player/service calls and no file writes.
#import <Foundation/Foundation.h>
#include <stdint.h>

static uint8_t result = 1;
static uint32_t calls = 0, command = 0, options = 0, mainThread = 0;

void TLMediaFixtureReset(uint8_t value) {
    result = value;
    calls = command = options = mainThread = 0;
}
uint32_t TLMediaFixtureCalls(void) { return calls; }
uint32_t TLMediaFixtureCommand(void) { return command; }
uint32_t TLMediaFixtureOptions(void) { return options; }
uint32_t TLMediaFixtureMainThread(void) { return mainThread; }

#ifndef MEDIA_REMOTE_MISSING_SYMBOL
// Independent C declaration matches the audited Boolean / enum32 / ObjC ABI.
uint8_t MRMediaRemoteSendCommand(uint32_t value, NSDictionary *userInfo) {
    ++calls;
    command = value;
    options = userInfo != nil;
    mainThread = [NSThread isMainThread];
    return result;
}
#endif
