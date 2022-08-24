const init = @import("main.zig").init;

test {
    init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
}
