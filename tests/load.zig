const std = @import("std");
const testing = std.testing;
const windows = std.os.windows;
const builtin = @import("builtin");

const dotenv = @import("dotenv");

fn setEnvForTest(
    allocator: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
) !void {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const w_key = try std.unicode.utf8ToUtf16LeAllocZ(allocator, key);
    defer allocator.free(w_key);
    const w_value = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(w_value);

    if (SetEnvironmentVariableW(w_key.ptr, w_value.ptr) == .FALSE) {
        return error.Unexpected;
    }
}

fn getEnvForTest(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const w_key = try std.unicode.utf8ToUtf16LeAllocZ(allocator, key);
    defer allocator.free(w_key);

    var stack_buffer: [512]u16 = undefined;
    const needed = GetEnvironmentVariableW(w_key.ptr, &stack_buffer, stack_buffer.len);
    if (needed == 0) return error.EnvironmentVariableNotFound;
    if (needed < stack_buffer.len) {
        return try std.unicode.utf16LeToUtf8Alloc(allocator, stack_buffer[0..needed]);
    }

    const buffer = try allocator.alloc(u16, needed);
    defer allocator.free(buffer);
    const copied = GetEnvironmentVariableW(w_key.ptr, buffer.ptr, @intCast(buffer.len));
    if (copied == 0) return error.EnvironmentVariableNotFound;
    return try std.unicode.utf16LeToUtf8Alloc(allocator, buffer[0..copied]);
}

extern "kernel32" fn SetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpValue: ?[*:0]const u16,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn GetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpBuffer: [*]u16,
    nSize: u32,
) callconv(.winapi) windows.DWORD;

test "load: parse local fixture" {
    var io_impl: std.Io.Threaded = .init(testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var env = try dotenv.parseFromPath(io, testing.allocator, "tests/fixtures/valid/local.env", .{});
    defer env.deinit();

    try testing.expectEqualStrings("local_basic", env.get("BASIC").?);
    try testing.expectEqualStrings("local", env.get("LOCAL").?);
}

test "load: parse vault fixture" {
    var io_impl: std.Io.Threaded = .init(testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var env = try dotenv.parseFromPath(io, testing.allocator, "tests/fixtures/valid/vault.env", .{});
    defer env.deinit();

    const value = env.get("DOTENV_VAULT_DEVELOPMENT").?;
    try testing.expect(value.len > 16);
}

test "load: multiline fixture fails on single-quoted multiline (dialect choice)" {
    var io_impl: std.Io.Threaded = .init(testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    try testing.expectError(
        dotenv.DotEnvError.UnterminatedString,
        dotenv.parseFromPath(io, testing.allocator, "tests/fixtures/valid/multiline.env", .{}),
    );
}

test "loadIntoProcess: respects overwrite flag" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const input =
        "__DOTENV_TEST_LOAD_KEY=from_file\n" ++
        "__DOTENV_TEST_LOAD_OTHER=other\n";

    var env = try dotenv.parseFromSlice(testing.allocator, input, .{});
    defer env.deinit();

    try setEnvForTest(testing.allocator, "__DOTENV_TEST_LOAD_KEY", "existing");

    try env.loadIntoProcess(false);
    const no_overwrite = try getEnvForTest(testing.allocator, "__DOTENV_TEST_LOAD_KEY");
    defer testing.allocator.free(no_overwrite);
    try testing.expectEqualStrings("existing", no_overwrite);

    try env.loadIntoProcess(true);
    const overwrite = try getEnvForTest(testing.allocator, "__DOTENV_TEST_LOAD_KEY");
    defer testing.allocator.free(overwrite);
    try testing.expectEqualStrings("from_file", overwrite);

    const other = try getEnvForTest(testing.allocator, "__DOTENV_TEST_LOAD_OTHER");
    defer testing.allocator.free(other);
    try testing.expectEqualStrings("other", other);
}

test "load: invalid fixtures fail to parse" {
    var io_impl: std.Io.Threaded = .init(testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    const invalid_paths = [_][]const u8{
        "tests/fixtures/invalid/bad-interpolation.env",
        "tests/fixtures/invalid/bad-key-chars.env",
        "tests/fixtures/invalid/control-chars.env",
        "tests/fixtures/invalid/duplicate-export.env",
        "tests/fixtures/invalid/empty-key.env",
        "tests/fixtures/invalid/invalid-escape-seq.env",
        "tests/fixtures/invalid/missing-equals.env",
        "tests/fixtures/invalid/multiline-no-close.env",
        "tests/fixtures/invalid/null-byte.env",
        "tests/fixtures/invalid/unclosed-quotes.env",
    };

    for (invalid_paths) |path| {
        if (dotenv.parseFromPath(io, testing.allocator, path, .{})) |env| {
            var parsed = env;
            defer parsed.deinit();

            if (std.mem.endsWith(u8, path, "unclosed-quotes.env")) {
                const db = parsed.get("DATABASE_URL") orelse {
                    return error.TestUnexpectedResult;
                };

                try testing.expect(std.mem.indexOf(u8, db, "SECRET_KEY=") != null);
                try testing.expect(parsed.get("SECRET_KEY") == null);
                continue;
            }

            std.debug.print("expected parse error for fixture: {s}\\n", .{path});
            return error.TestUnexpectedResult;
        } else |err| {
            switch (err) {
                error.OutOfMemory => return err,
                else => {},
            }
        }
    }
}
