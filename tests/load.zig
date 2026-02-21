const std = @import("std");
const testing = std.testing;

const builtin = @import("builtin");

const dotenv = @import("dotenv");

fn setEnvForTest(allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const w = std.os.windows;
    const w_key = try std.unicode.utf8ToUtf16LeAllocZ(allocator, key);
    defer allocator.free(w_key);
    const w_value = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(w_value);

    if (w.kernel32.SetEnvironmentVariableW(w_key.ptr, w_value.ptr) == 0) {
        return error.Unexpected;
    }
}

test "load: parse local fixture" {
    var env = try dotenv.parseFromPath(testing.allocator, "tests/fixtures/valid/local.env", .{});
    defer env.deinit();

    try testing.expectEqualStrings("local_basic", env.get("BASIC").?);
    try testing.expectEqualStrings("local", env.get("LOCAL").?);
}

test "load: parse vault fixture" {
    var env = try dotenv.parseFromPath(testing.allocator, "tests/fixtures/valid/vault.env", .{});
    defer env.deinit();

    const value = env.get("DOTENV_VAULT_DEVELOPMENT").?;
    try testing.expect(value.len > 16);
}

test "load: multiline fixture fails on single-quoted multiline (dialect choice)" {
    try testing.expectError(
        dotenv.DotEnvError.UnterminatedString,
        dotenv.parseFromPath(testing.allocator, "tests/fixtures/valid/multiline.env", .{}),
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
    const no_overwrite = try std.process.getEnvVarOwned(testing.allocator, "__DOTENV_TEST_LOAD_KEY");
    defer testing.allocator.free(no_overwrite);
    try testing.expectEqualStrings("existing", no_overwrite);

    try env.loadIntoProcess(true);
    const overwrite = try std.process.getEnvVarOwned(testing.allocator, "__DOTENV_TEST_LOAD_KEY");
    defer testing.allocator.free(overwrite);
    try testing.expectEqualStrings("from_file", overwrite);

    const other = try std.process.getEnvVarOwned(testing.allocator, "__DOTENV_TEST_LOAD_OTHER");
    defer testing.allocator.free(other);
    try testing.expectEqualStrings("other", other);
}
