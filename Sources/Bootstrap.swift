import Dispatch

// dyld consumes a retained C function-pointer table, not a lazy Swift global.
// Keep private-class/UIKit work out of the loader callback itself.
@_used
@_section("__DATA,__mod_init_func")
private var tapLockInitializer: @convention(c) () -> Void = {
    DispatchQueue.main.async {
        TapLockRuntime.activate()
    }
}
