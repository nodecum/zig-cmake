const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        invalid,
        identifier,
        string,
        separator,
        eof,
        l_paren,
        r_paren,
        //l_brace,
        //r_brace,
        //plus_equal,
        //linksection_comment,
        //bracket_comment,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .identifier,
                .string,
                .separator,
                .eof,
                // .line_comment,
                // .bracket_comment,
                => null,
                .l_paren => "(",
                .r_paren => ")",
                //.l_brace => "{",
                //.r_brace => "}",
                //.plus_equal => "+=",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid bytes",
                .identifier => "an identifier",
                .string => "a string",
                .separator => "separator",
                .eof => "EOF",
                //.line_comment, .bracket_comment => "a document comment",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,
    paren_depth: u8,

    /// For debugging purposes
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present
        const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
        return Tokenizer{
            .buffer = buffer,
            .index = src_start,
            .paren_depth = 0, // depth of parentheses 0 is command level, >0 are arguments
        };
    }

    const State = enum {
        start,
        identifier,
        string,
        separator,
        line_comment,
        //bracket_comment_start,
        //bracket_comment,
        //equal,
        //..plus,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            if (c == 0) {
                if (self.index != self.buffer.len) {
                    result.tag = .invalid;
                    result.loc.start = self.index;
                    self.index += 1;
                    result.loc.end = self.index;
                } else {
                    if (state == .separator or state == .line_comment) {
                        result.tag = .eof;
                        result.loc.start = self.index;
                    }
                    result.loc.end = self.index;
                }
                return result;
            }
            switch (state) {
                .start => switch (c) {
                    ' ', '\t', '\n', '\r' => {
                        state = .separator;
                        if (self.paren_depth > 0) {
                            result.tag = .separator;
                        }
                    },
                    'a'...'z', 'A'...'Z', '_' => if (self.paren_depth == 0) {
                        result.tag = .identifier;
                        state = .identifier;
                    } else {
                        result.tag = .string;
                        state = .string;
                    },
                    '0'...'9', '/' => if (self.paren_depth == 0) {
                        result.tag = .invalid;
                        result.loc.end = self.index;
                        self.index += 1;
                        return result;
                    } else {
                        result.tag = .string;
                        state = .string;
                    },

                    '(' => {
                        self.paren_depth += 1;
                        result.tag = .l_paren;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        if (self.paren_depth > 0) {
                            self.paren_depth -= 1;
                            result.tag = .r_paren;
                        } else {
                            result.tag = .invalid;
                        }
                        self.index += 1;
                        break;
                    },
                    '#' => {
                        state = .line_comment;
                    },
                    else => {
                        result.tag = .invalid;
                        result.loc.end = self.index;
                        self.index += 1;
                        return result;
                    },
                },
                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '_' => {},
                    else => break,
                },
                .string => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9', '.', '/' => {},
                    else => break,
                },
                .separator => switch (c) {
                    '\n', '\r', ' ', '\t' => {},
                    else => if (self.paren_depth == 0) {
                        state = .start;
                        result.loc.start = self.index;
                        // reread char
                        self.index -= 1;
                    } else {
                        break;
                    },
                },
                .line_comment => switch (c) {
                    '\n', '\r' => {
                        state = .start;
                        result.loc.start = self.index + 1;
                    },
                    else => {},
                },
            }
        }
        result.loc.end = self.index;
        return result;
    }
};

test "identifier a" {
    try testTokenize("a", &.{.identifier});
}

test "identifier ab" {
    try testTokenize("ab", &.{.identifier});
}

test "identifier ab c" {
    try testTokenize("ab c", &.{ .identifier, .identifier });
}

test "identifier and comment" {
    try testTokenize("hello # comment", &.{.identifier});
}

test "comment and identifier" {
    try testTokenize(
        \\# un comment
        \\abc
    , &.{.identifier});
}

//test "equal" {
//    try testTokenize("a = b", &.{ .string, .equal, .string });
//}
//
//test "newline" {
//    try testTokenize(
//        \\a = one.c # comment
//        \\b = two.c foo.h
//        \\c = three.c
//    , &.{
//        .string,  .equal,  .string, .newline,
//        .string,  .equal,  .string, .string,
//        .newline, .string, .equal,  .string,
//    });
//}
fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}
