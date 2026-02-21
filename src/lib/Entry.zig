/// A single key/value dotenv entry.
///
/// Both slices are owned by `DotEnv`'s internal arena and remain valid until
/// `DotEnv.deinit()` is called.
pub const Entry = @This();

key: []const u8,
value: []const u8,
