const std = @import("std");
const ParseOptions = @import("ParseOptions.zig");
const DotEnv = @import("DotEnv.zig");
const Allocator = std.mem.Allocator;
const enums = @import("enums.zig");
const errors = @import("errors.zig");
const DotEnvError = errors.DotEnvError;

const Parser = @This();

env: *DotEnv,
scratch_allocator: Allocator,
input: []const u8,
options: ParseOptions,

idx: usize,
state: enums.ParserState,
interpolation_return_state: enums.InterpolationReturnState,

key_buf: std.ArrayList(u8),
value_buf: std.ArrayList(u8),
interpolation_buf: std.ArrayList(u8),

seen_equal: bool,
value_mode: enums.ValueMode,
ignoring_until_newline: bool,

pub fn init(env: *DotEnv, scratch_allocator: Allocator, input: []const u8, options: ParseOptions) Parser {
    return .{
        .env = env,
        .scratch_allocator = scratch_allocator,
        .input = input,
        .options = options,
        .idx = 0,
        .state = .start,
        .interpolation_return_state = .in_unquoted_value,
        .key_buf = .empty,
        .value_buf = .empty,
        .interpolation_buf = .empty,
        .seen_equal = false,
        .value_mode = .none,
        .ignoring_until_newline = false,
    };
}

const utils = @import("utils.zig");

pub fn parse(self: *Parser) !void {
    defer self.key_buf.deinit(self.scratch_allocator);
    defer self.value_buf.deinit(self.scratch_allocator);
    defer self.interpolation_buf.deinit(self.scratch_allocator);

    while (self.idx < self.input.len) {
        const ch = self.input[self.idx];

        switch (self.state) {
            .start => {
                if (ch == ' ' or ch == '\t' or ch == '\r') {
                    self.idx += 1;
                    continue;
                }
                if (ch == '\n') {
                    self.idx += 1;
                    self.resetLineState();
                    continue;
                }
                if (ch == '#') {
                    self.state = .in_comment;
                    self.idx += 1;
                    continue;
                }

                if (self.startsWithExportKeyword()) {
                    self.idx += "export".len;
                    self.skipHorizontalWhitespace();
                    continue;
                }

                try self.beginEntryIfNeeded();
                if (!utils.isKeyStartChar(ch)) {
                    return DotEnvError.InvalidKeyCharacter;
                }
                try self.key_buf.append(self.scratch_allocator, ch);
                self.state = .in_key;
                self.idx += 1;
            },
            .in_comment => {
                if (ch == '\n') {
                    self.idx += 1;
                    self.resetLineState();
                    self.state = .start;
                    self.ignoring_until_newline = false;
                } else {
                    self.idx += 1;
                }
            },
            .in_key => {
                if (utils.isKeyContinueChar(ch)) {
                    try self.key_buf.append(self.scratch_allocator, ch);
                    self.idx += 1;
                    continue;
                }
                if (ch == '=') {
                    self.seen_equal = true;
                    self.state = .pre_value;
                    self.idx += 1;
                    continue;
                }
                if (ch == ' ' or ch == '\t' or ch == '\r') {
                    self.state = .pre_value;
                    self.idx += 1;
                    continue;
                }
                return DotEnvError.InvalidKeyCharacter;
            },
            .pre_value => {
                if (!self.seen_equal) {
                    if (ch == ' ' or ch == '\t' or ch == '\r') {
                        self.idx += 1;
                        continue;
                    }
                    if (ch == '=') {
                        self.seen_equal = true;
                        self.idx += 1;
                        continue;
                    }
                    return DotEnvError.MissingEquals;
                }

                if (ch == ' ' or ch == '\t' or ch == '\r') {
                    self.idx += 1;
                    continue;
                }
                if (ch == '\n') {
                    try self.finalizeEntry();
                    self.idx += 1;
                    self.resetLineState();
                    self.state = .start;
                    continue;
                }
                if (ch == '#') {
                    try self.finalizeEntry();
                    self.state = .in_comment;
                    self.idx += 1;
                    continue;
                }
                if (ch == '"') {
                    self.value_mode = .double_quoted;
                    self.state = .in_double_quoted_value;
                    self.idx += 1;
                    continue;
                }
                if (ch == '\'') {
                    self.value_mode = .single_quoted;
                    self.state = .in_single_quoted_value;
                    self.idx += 1;
                    continue;
                }

                self.value_mode = .unquoted;
                self.state = .in_unquoted_value;
            },
            .in_unquoted_value => {
                if (ch == '\n') {
                    try self.finalizeEntry();
                    self.idx += 1;
                    self.resetLineState();
                    self.state = .start;
                    continue;
                }
                if (ch == '#') {
                    try self.finalizeEntry();
                    self.state = .in_comment;
                    self.idx += 1;
                    continue;
                }
                if (ch == '$' and self.options.interpolate) {
                    self.interpolation_return_state = .in_unquoted_value;
                    self.state = .in_interpolation;
                    self.idx += 1;
                    continue;
                }

                try self.value_buf.append(self.scratch_allocator, ch);
                self.idx += 1;
            },
            .in_double_quoted_value => {
                if (ch == '"') {
                    try self.finalizeEntry();
                    self.state = .in_comment;
                    self.ignoring_until_newline = true;
                    self.idx += 1;
                    continue;
                }
                if (ch == '\\') {
                    self.state = .in_escape;
                    self.idx += 1;
                    continue;
                }
                if (ch == '$' and self.options.interpolate) {
                    self.interpolation_return_state = .in_double_quoted_value;
                    self.state = .in_interpolation;
                    self.idx += 1;
                    continue;
                }

                try self.value_buf.append(self.scratch_allocator, ch);
                self.idx += 1;
            },
            .in_single_quoted_value => {
                if (ch == '\'') {
                    try self.finalizeEntry();
                    self.state = .in_comment;
                    self.ignoring_until_newline = true;
                    self.idx += 1;
                    continue;
                }
                if (ch == '\n') {
                    return DotEnvError.UnterminatedString;
                }
                try self.value_buf.append(self.scratch_allocator, ch);
                self.idx += 1;
            },
            .in_escape => {
                if (self.idx >= self.input.len) {
                    return DotEnvError.UnterminatedString;
                }

                const esc = self.input[self.idx];
                switch (esc) {
                    'n' => try self.value_buf.append(self.scratch_allocator, '\n'),
                    't' => try self.value_buf.append(self.scratch_allocator, '\t'),
                    'r' => try self.value_buf.append(self.scratch_allocator, '\r'),
                    '\\' => try self.value_buf.append(self.scratch_allocator, '\\'),
                    '"' => try self.value_buf.append(self.scratch_allocator, '"'),
                    '$' => try self.value_buf.append(self.scratch_allocator, '$'),
                    else => {
                        switch (self.options.invalid_escape_behavior) {
                            .@"error" => return DotEnvError.InvalidEscapeSequence,
                            .passthrough => {
                                try self.value_buf.append(self.scratch_allocator, '\\');
                                try self.value_buf.append(self.scratch_allocator, esc);
                            },
                        }
                    },
                }
                self.idx += 1;
                self.state = .in_double_quoted_value;
            },
            .in_interpolation => {
                try self.parseInterpolation();
                self.state = switch (self.interpolation_return_state) {
                    .in_unquoted_value => .in_unquoted_value,
                    .in_double_quoted_value => .in_double_quoted_value,
                };
            },
        }
    }

    switch (self.state) {
        .start, .in_comment => {
            if (self.hasPendingEntry()) {
                try self.finalizeEntry();
            }
        },
        .in_key => return DotEnvError.MissingEquals,
        .pre_value => {
            if (!self.seen_equal) return DotEnvError.MissingEquals;
            try self.finalizeEntry();
        },
        .in_unquoted_value => try self.finalizeEntry(),
        .in_double_quoted_value, .in_single_quoted_value, .in_escape => return DotEnvError.UnterminatedString,
        .in_interpolation => unreachable,
    }
}

fn parseInterpolation(self: *Parser) !void {
    self.interpolation_buf.clearRetainingCapacity();

    if (self.idx >= self.input.len) {
        try self.value_buf.append(self.scratch_allocator, '$');
        return;
    }

    if (self.input[self.idx] == '{') {
        self.idx += 1;
        if (self.idx >= self.input.len) return DotEnvError.UnterminatedString;

        while (self.idx < self.input.len and self.input[self.idx] != '}') : (self.idx += 1) {
            const ch = self.input[self.idx];
            if (self.interpolation_buf.items.len == 0) {
                if (!utils.isKeyStartChar(ch)) {
                    return DotEnvError.InvalidKeyCharacter;
                }
            } else if (!utils.isKeyContinueChar(ch)) {
                return DotEnvError.InvalidKeyCharacter;
            }
            try self.interpolation_buf.append(self.scratch_allocator, ch);
        }

        if (self.idx >= self.input.len or self.input[self.idx] != '}') {
            return DotEnvError.UnterminatedString;
        }
        self.idx += 1;
    } else {
        const first = self.input[self.idx];
        if (!utils.isKeyStartChar(first)) {
            try self.value_buf.append(self.scratch_allocator, '$');
            return;
        }

        try self.interpolation_buf.append(self.scratch_allocator, first);
        self.idx += 1;
        while (self.idx < self.input.len and utils.isKeyContinueChar(self.input[self.idx])) : (self.idx += 1) {
            try self.interpolation_buf.append(self.scratch_allocator, self.input[self.idx]);
        }
    }

    const resolved = try self.resolveVariable(self.interpolation_buf.items);
    try self.value_buf.appendSlice(self.scratch_allocator, resolved);
}

fn resolveVariable(self: *Parser, name: []const u8) ![]const u8 {
    if (self.env.entries.get(name)) |v| {
        return v;
    }

    const env_value = std.process.getEnvVarOwned(self.scratch_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            return switch (self.options.undefined_variable_behavior) {
                .@"error" => DotEnvError.UndefinedVariable,
                .empty_string => "",
            };
        },
        else => return err,
    };
    defer self.scratch_allocator.free(env_value);

    return try self.env.arena.allocator().dupe(u8, env_value);
}

fn skipHorizontalWhitespace(self: *Parser) void {
    while (self.idx < self.input.len) {
        const ch = self.input[self.idx];
        if (ch == ' ' or ch == '\t' or ch == '\r') {
            self.idx += 1;
            continue;
        }
        break;
    }
}

fn startsWithExportKeyword(self: *Parser) bool {
    if (!std.mem.startsWith(u8, self.input[self.idx..], "export")) return false;
    const end = self.idx + "export".len;
    if (end >= self.input.len) return false;
    const next = self.input[end];
    return next == ' ' or next == '\t' or next == '\r';
}

fn beginEntryIfNeeded(self: *Parser) !void {
    if (self.key_buf.items.len == 0 and self.value_buf.items.len == 0 and self.value_mode == .none and !self.seen_equal) {
        self.key_buf.clearRetainingCapacity();
        self.value_buf.clearRetainingCapacity();
        self.value_mode = .none;
        self.seen_equal = false;
    }
}

fn hasPendingEntry(self: *Parser) bool {
    return self.key_buf.items.len > 0 or self.seen_equal;
}

fn finalizeEntry(self: *Parser) !void {
    if (self.key_buf.items.len == 0) {
        return DotEnvError.EmptyKey;
    }
    if (!self.seen_equal) {
        return DotEnvError.MissingEquals;
    }
    try utils.validateKey(self.key_buf.items);

    const value_to_store: []const u8 = switch (self.value_mode) {
        .none => "",
        .unquoted => std.mem.trim(u8, self.value_buf.items, " \t\r"),
        .double_quoted, .single_quoted => self.value_buf.items,
    };

    const owned_key = try self.env.arena.allocator().dupe(u8, self.key_buf.items);
    const owned_value = try self.env.arena.allocator().dupe(u8, value_to_store);
    try self.env.entries.put(self.env.arena.allocator(), owned_key, owned_value);

    self.key_buf.clearRetainingCapacity();
    self.value_buf.clearRetainingCapacity();
    self.value_mode = .none;
    self.seen_equal = false;
}

fn resetLineState(self: *Parser) void {
    self.key_buf.clearRetainingCapacity();
    self.value_buf.clearRetainingCapacity();
    self.seen_equal = false;
    self.value_mode = .none;
}
