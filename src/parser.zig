//! Generic parser combinators
//! Heavily inspired by <https://devlog.hexops.com/2021/zig-parser-combinators-and-why-theyre-awesome/>

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    EndOfStream,
} || std.mem.Allocator.Error;


pub fn Parser(comptime Value: type, comptime Reader: type) type {
    return struct {
        const Self = @This();
        _parse: fn(self: *Self, allocator: Allocator, src: *Reader) callconv(.Inline) Error!?Value,

        pub fn parse(self: *Self, allocator: Allocator, src: *Reader) callconv(.Inline) Error!?Value {
            std.debug.print("parsing\n", .{});
            return self._parse(self, allocator, src);
        }
    };
}

pub fn Literal(comptime Reader: type) type {
    return struct {
        parser: Parser([]const u8, Reader) = .{
            ._parse = parse
        },
        want: []const u8,

        const Self = @This();

        fn parse(parser: *Parser([]const u8, Reader), allocator: Allocator, src: *Reader) callconv(.Inline) Error!?[]const u8{
            const self = @fieldParentPtr(Self, "parser", parser);
            const buf = try allocator.alloc(u8, self.want.len);
            errdefer allocator.free(buf);
            const read = try src.reader().readAll(buf);
            if (read < self.want.len or !std.mem.eql(u8, buf, self.want)) {
                try src.seekableStream().seekBy(-@intCast(i64, read));
                allocator.free(buf);
                return null;
            }
            return buf;
        }

        pub fn init(want: []const u8) Self {
            return Self {
                .want = want,
            };
        }
    };
}

pub fn All(comptime Value: type, comptime Reader: type) type {
    return struct {
        parser: Parser(Value, Reader) = .{
            ._parse = parse
        },
        parsers: []*Parser(Value, Reader),

        const Self = @This();

        fn parse(parser: *Parser(Value, Reader), allocator: Allocator, src: *Reader) callconv(.Inline) Error!?Value {
            const self = @fieldParentPtr(Self, "parser", parser);
            std.debug.assert(self.parsers.len != 0);
            var matched: []const u8 = undefined;
            for (self.parsers) |optional_parser| {
                const result = try optional_parser.parse(allocator, src);
                if (result) |matched_str| {
                    matched = matched_str;
                } else {
                    // TODO: rewind reader to where we started
                    return null;
                }
            }
            return matched;
        }

        pub fn init(parsers: []*Parser(Value, Reader)) Self {
            return Self {
                .parsers = parsers,
            };
        }
    };
}

pub fn OneOf(comptime Value: type, comptime Reader: type) type {
    return struct {
        parser: Parser(Value, Reader) = .{
            ._parse = parse
        },
        parsers: []*Parser(Value, Reader),

        const Self = @This();

        fn parse(parser: *Parser(Value, Reader), allocator: Allocator, src: *Reader) callconv(.Inline) Error!?Value {
            const self = @fieldParentPtr(Self, "parser", parser);
            for (self.parsers) |optional_parser| {
                const result = try optional_parser.parse(allocator, src);
                if (result != null) {
                    return result;
                }
            }
            return null;
        }

        pub fn init(parsers: []*Parser(Value, Reader)) Self {
            return Self {
                .parsers = parsers,
            };
        }
    };
}
