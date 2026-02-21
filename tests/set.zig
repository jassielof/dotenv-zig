const std = @import("std");
const testing = std.testing;

const dotenv = @import("dotenv");

test "set: put and get" {
    var env = try dotenv.parseFromSlice(testing.allocator, "", .{});
    defer env.deinit();

    try env.put("FIRST", "1");
    try env.put("SECOND", "2");
    try env.put("FIRST", "updated");

    try testing.expectEqualStrings("updated", env.get("FIRST").?);
    try testing.expectEqualStrings("2", env.get("SECOND").?);
}

test "set: reject invalid key" {
    var env = try dotenv.parseFromSlice(testing.allocator, "", .{});
    defer env.deinit();

    try testing.expectError(dotenv.DotEnvError.InvalidKeyCharacter, env.put("1INVALID", "x"));
}

test "set: serialize preserves insertion order and auto quote strategy" {
    var env = try dotenv.parseFromSlice(testing.allocator, "", .{});
    defer env.deinit();

    try env.put("ALPHA", "plain");
    try env.put("BETA", "line\nbreak");
    try env.put("GAMMA", "has#hash");
    try env.put("DELTA", "O'Reilly");

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    const writer = out.writer(testing.allocator);
    try env.serialize(&writer, .{});

    const text = out.items;
    try testing.expect(std.mem.indexOf(u8, text, "ALPHA=plain\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "BETA=\"line\\nbreak\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "GAMMA=\"has#hash\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "DELTA='O'Reilly'\n") != null);

    const p_alpha = std.mem.indexOf(u8, text, "ALPHA=plain\n").?;
    const p_beta = std.mem.indexOf(u8, text, "BETA=\"line\\nbreak\"\n").?;
    const p_gamma = std.mem.indexOf(u8, text, "GAMMA=\"has#hash\"\n").?;
    const p_delta = std.mem.indexOf(u8, text, "DELTA='O'Reilly'\n").?;
    try testing.expect(p_alpha < p_beta and p_beta < p_gamma and p_gamma < p_delta);
}

test "set: serialize quote override" {
    var env = try dotenv.parseFromSlice(testing.allocator, "", .{});
    defer env.deinit();

    try env.put("KEY", "value");

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    const writer = out.writer(testing.allocator);
    try env.serialize(&writer, .{ .quote_style = .double });

    try testing.expectEqualStrings("KEY=\"value\"\n", out.items);
}
