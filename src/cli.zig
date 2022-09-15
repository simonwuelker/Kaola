//! Commandline argument parser
const std = @import("std");
const fixedBufferStream = std.io.fixedBufferStream;
const Allocator = std.mem.Allocator;

const parser = @import("parser.zig");
const Parser = parser.Parser;
const Literal = parser.Literal;
const OneOf = parser.OneOf;
const All = parser.All;

// fn flag(comptime Reader: type, short_name: []const u8, long_name: []const u8) Parser([]const u8, Reader) {
//     const combinator = OneOf([]const u8, @TypeOf(Reader)).init(&.{
//         &All([]const u8, Reader).init(&.{ &Literal(Reader).init("-").parser, &Literal(Reader).init(short_name).parser }),
//         &All([]const u8, Reader).init(&.{ &Literal(Reader).init("--").parser, &Literal(Reader).init(long_name).parser }),
//     });
//     return combinator.parser;
// }

fn flag(short_name: []const u8, long_name: []const u8, comptime Reader: type) Parser([]const u8, Reader) {
    // var one_of = OneOf([]const u8, Reader).init(&.{
    //     &Literal(Reader).init("dog").parser,
    //     &Literal(Reader).init("sheep").parser,
    //     &Literal(Reader).init(val).parser,
    // });
    _ = long_name;
    const one_of = OneOf([]const u8, Reader).init(&.{
        &All([]const u8, Reader).init(&.{ &Literal(Reader).init("-").parser, &Literal(Reader).init(short_name).parser }).parser,
        // &All([]const u8, Reader).init(&.{ &Literal(Reader).init("--").parser, &Literal(Reader).init(long_name).parser }).parser,
    });
    return one_of.parser;
}

pub const CommandLineArguments = struct {
    show_help: bool,
    show_version: bool,

    const Self = @This();

    fn default() Self {
        return Self {
            .show_help = false,
            .show_version = false,
        };
    }

    pub fn parse(allocator: Allocator) !Self {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        var parsed = Self.default();

        while (args.next(allocator)) |argument_or_error| {
            const arg = try argument_or_error;
            std.debug.print("{s}\n", .{arg});
            var reader = fixedBufferStream(arg);
            if (try flag("h", "help", @TypeOf(reader)).parse(allocator, &reader)) |_| {
                parsed.show_help = true;
            }
            // if (try flag("v", "version", @TypeOf(reader)).parse(allocator, &reader)) |_| {
            //     parsed.show_version = true;
            // }
            allocator.free(arg);
        }

        return parsed;
    }
};


