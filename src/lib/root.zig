const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

pub const DotEnv = @import("DotEnv.zig");
pub const ParseOptions = @import("ParseOptions.zig");

const enums = @import("enums.zig");
pub const UndefinedVariableBehavior = enums.UndefinedVariableBehavior;
pub const InvalidEscapeBehavior = enums.InvalidEscapeBehavior;
pub const QuoteStyle = enums.QuoteStyle;

const errors = @import("errors.zig");
pub const DotEnvError = errors.DotEnvError;

/// Parse dotenv content from an in-memory string.
pub fn parseFromSlice(allocator: Allocator, input: []const u8, options: ParseOptions) !DotEnv {
    return DotEnv.parseFromSlice(allocator, input, options);
}

/// Parse dotenv content from file path.
pub fn parseFromPath(allocator: Allocator, path: []const u8, options: ParseOptions) !DotEnv {
    return DotEnv.parseFromPath(allocator, path, options);
}
