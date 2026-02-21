//! Ordered dotenv key/value container.
//!
//! Memory model:
//! - All keys and values are owned by an internal arena allocator.
//! - Slices returned from `get()` are invalid after `deinit()`.
const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const SerializeOptions = @import("SerializeOptions.zig");
const Parser = @import("Parser.zig");
const ParseOptions = @import("ParseOptions.zig");
const errors = @import("errors.zig");
const utils = @import("utils.zig");

const DotEnv = @This();

/// The arena allocator
arena: std.heap.ArenaAllocator,
/// The map of entries
entries: std.StringArrayHashMapUnmanaged([]const u8),

/// Parse dotenv content from an in-memory UTF-8/byte buffer.
pub fn parseFromSlice(allocator: Allocator, input: []const u8, options: ParseOptions) !DotEnv {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var env = DotEnv{
        .arena = arena,
        .entries = .{},
    };
    errdefer env.arena.deinit();

    var parser = Parser.init(&env, allocator, input, options);
    try parser.parse();
    return env;
}

/// Parse dotenv content from a file path.
pub fn parseFromPath(allocator: Allocator, path: []const u8, options: ParseOptions) !DotEnv {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(data);
    return DotEnv.parseFromSlice(allocator, data, options);
}

/// Load all entries into the current process environment.
///
/// When `overwrite` is false, existing process variables are not replaced.
pub fn loadIntoProcess(self: *DotEnv, overwrite: bool) !void {
    var it = self.entries.iterator();
    while (it.next()) |kv| {
        if (!overwrite) {
            const existing = std.process.getEnvVarOwned(self.arena.allocator(), kv.key_ptr.*) catch |err| switch (err) {
                error.EnvironmentVariableNotFound => null,
                else => return err,
            };
            if (existing != null) {
                continue;
            }
        }
        try setProcessEnvVar(self.arena.allocator(), kv.key_ptr.*, kv.value_ptr.*);
    }
}

fn setProcessEnvVar(allocator: Allocator, key: []const u8, value: []const u8) !void {
    switch (builtin.os.tag) {
        .windows => {
            const w = std.os.windows;
            const w_key = try std.unicode.utf8ToUtf16LeAllocZ(allocator, key);
            defer allocator.free(w_key);
            const w_value = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
            defer allocator.free(w_value);

            if (w.kernel32.SetEnvironmentVariableW(w_key.ptr, w_value.ptr) == 0) {
                return errors.DotEnvError.EnvironmentMutationFailed;
            }
        },
        else => return errors.DotEnvError.EnvironmentMutationFailed,
    }
}

/// Serialize dotenv content to any writer.
///
/// In auto mode, quoted value handling is:
/// - double-quoted if value contains `\n`, `\t`, `"`, or `#`
/// - single-quoted if value contains `'` and did not match double-quoted triggers
/// - unquoted otherwise
pub fn serialize(self: *const DotEnv, writer: anytype, options: SerializeOptions) !void {
    if (options.header_comment) |header| {
        try writer.writeAll("# ");
        try writer.writeAll(header);
        try writer.writeAll("\n");
    }
    if (options.include_timestamp_header) {
        try writer.print("# generated_at_unix={}\n", .{std.time.timestamp()});
    }

    const keys = self.entries.keys();
    const values = self.entries.values();
    var i: usize = 0;
    while (i < self.entries.count()) : (i += 1) {
        const key = keys[i];
        const value = values[i];

        try writer.writeAll(key);
        try writer.writeAll("=");

        const style = chooseQuoteStyle(value, options.quote_style);
        switch (style) {
            .unquoted => try writer.writeAll(value),
            .single => {
                try writer.writeAll("'");
                try writer.writeAll(value);
                try writer.writeAll("'");
            },
            .double => {
                try writer.writeAll("\"");
                try writeEscapedDoubleQuoted(writer, value);
                try writer.writeAll("\"");
            },
            .auto => unreachable,
        }

        try writer.writeAll("\n");
    }
}

fn writeEscapedDoubleQuoted(writer: anytype, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            '\r' => try writer.writeAll("\\r"),
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '$' => try writer.writeAll("\\$"),
            else => try writer.writeByte(ch),
        }
    }
}

const enums = @import("enums.zig");
fn chooseQuoteStyle(value: []const u8, override_style: enums.QuoteStyle) enums.QuoteStyle {
    if (override_style != .auto) return override_style;

    if (std.mem.indexOfAny(u8, value, "\n\t\"#") != null) return .double;
    if (std.mem.indexOfScalar(u8, value, '\'') != null) return .single;
    return .unquoted;
}

/// Serialize dotenv content directly to a file path.
pub fn serializeToPath(self: *const DotEnv, path: []const u8, options: SerializeOptions) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;

    try self.serialize(writer, options);
    try writer.flush();
}

/// Get a value by key. Returned slice is owned by `DotEnv`.
pub fn get(self: *const DotEnv, key: []const u8) ?[]const u8 {
    return self.entries.get(key);
}

/// Insert or update a key/value pair.
///
/// Key is validated with `[A-Za-z_][A-Za-z0-9_]*`.
pub fn put(self: *DotEnv, key: []const u8, value: []const u8) !void {
    utils.validateKey(key) catch |err| return err;

    const owned_key = try self.arena.allocator().dupe(u8, key);
    const owned_value = try self.arena.allocator().dupe(u8, value);
    try self.entries.put(self.arena.allocator(), owned_key, owned_value);
}

/// Release all memory owned by this container.
pub fn deinit(self: *DotEnv) void {
    self.entries.deinit(self.arena.allocator());
    self.arena.deinit();
    self.* = undefined;
}
