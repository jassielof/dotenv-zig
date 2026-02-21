const std = @import("std");
const testing = std.testing;

comptime {
    _ = @import("load.zig");
    // _ = @import("set.zig");
}

test {
    testing.refAllDecls(@This());
}
