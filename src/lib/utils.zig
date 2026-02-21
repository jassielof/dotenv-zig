const errors = @import("errors.zig");

pub fn isKeyStartChar(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or ch == '_';
}

pub fn isKeyContinueChar(ch: u8) bool {
    return isKeyStartChar(ch) or (ch >= '0' and ch <= '9');
}

pub fn validateKey(key: []const u8) errors.DotEnvError!void {
    if (key.len == 0) return errors.DotEnvError.EmptyKey;
    if (!isKeyStartChar(key[0])) return errors.DotEnvError.InvalidKeyCharacter;
    var i: usize = 1;
    while (i < key.len) : (i += 1) {
        if (!isKeyContinueChar(key[i])) return errors.DotEnvError.InvalidKeyCharacter;
    }
}
