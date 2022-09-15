const std = @import("std");
const ArrayList = std.ArrayList;

const bitboard = @import("bitboard.zig");

const board = @import("board.zig");
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;

const movegen = @import("movegen.zig");
const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");

const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

const parser = @import("parser.zig");
const Literal = parser.Literal;
const OneOf = parser.OneOf;
const All = parser.All;
const Parser = parser.Parser;

const CommandLineArguments = @import("cli.zig").CommandLineArguments;

const fixedBufferStream = std.io.fixedBufferStream;

pub fn init() void {
    // bitboard.init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
}


pub fn main() !void {
    init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    const a = try CommandLineArguments.parse(allocator);
    _ = a;

    // var reader = fixedBufferStream("-v");
    // const Reader = @TypeOf(reader);

    // const y = All([]const u8, Reader).init(comptime &.{ &Literal(Reader).init("-").parser, &Literal(Reader).init("v").parser }).parser;
    // _ = y;

    // const combinator = OneOf([]const u8, Reader).init(comptime &.{
    //     &All([]const u8, Reader).init(&.{ &Literal(Reader).init("-").parser, &Literal(Reader).init("v").parser }).parser,
    //     &All([]const u8, Reader).init(&.{ &Literal(Reader).init("--").parser, &Literal(Reader).init("version").parser }).parser,
    // });

    // var one_of = x("abc", @TypeOf(reader));
    // _ = one_of;

    // var p = &combinator.parser;
    // var result = try p.parse(allocator, &reader);
    // try std.testing.expectEqualStrings("sheep", result.?);
    // if (result) |r| {
    //         allocator.free(r);
    // }
    // _ = combinator;
    _ = allocator;





    // will probably be overwritten by "ucinewgame" but it prevents undefined behaviour
    // and eases debugging to just define a default position
    // var position = Position.starting_position();
    // var board_rights = BoardRights.initial();
    // mainloop: while (true) {
    //     const command = try uci.next_command(&gpa);
    //     try switch (command) {
    //         GuiCommand.uci => {
    //             try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Mephisto" } }, &gpa);
    //             try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } }, &gpa);
    //             try send_command(EngineCommand.uciok, &gpa);
    //         },
    //         GuiCommand.isready => send_command(EngineCommand.readyok, &gpa),
    //         GuiCommand.debug => {},
    //         GuiCommand.newgame => {
    //             position = Position.starting_position();
    //             board_rights = BoardRights.initial();
    //         },
    //         GuiCommand.position => |state| {
    //             position = state.position;
    //             board_rights = state.board_rights;
    //         },
    //         GuiCommand.go => {
    //             // const best_move = searcher.search(game, 3);
    //             // try send_command(EngineCommand{ .bestmove = best_move });
    //         },
    //         GuiCommand.stop => {},
    //         GuiCommand.board => position.print(),
    //         GuiCommand.eval => {
    //             switch (board_rights.active_color) {
    //                 Color.white => std.debug.print("{d}\n", .{pesto.evaluate(Color.white, position)}),
    //                 Color.black => std.debug.print("{d}\n", .{pesto.evaluate(Color.black, position)}),
    //             }
    //         },
    //         GuiCommand.quit => break :mainloop,
    //     };
    // }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    const stderr = std.io.getStdErr().writer();
    stderr.print("The engine panicked, this is a bug.\nPlease file an issue at https://github.com/Wuelle/zigchess, including the debug information below.\nThanks ^_^\n", .{}) catch std.os.abort();
    const first_trace_addr = @returnAddress();
    std.debug.panicImpl(error_return_trace, first_trace_addr, msg);
}

test {
    init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
