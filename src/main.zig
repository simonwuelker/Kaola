const std = @import("std");
const ArrayList = std.ArrayList;
const Level = std.log.Level;
const Scope = std.log.default;
const OpenMode = std.fs.File.OpenMode;

const bitboard = @import("bitboard.zig");

const board = @import("board.zig");
const Move = board.Move;
const Position = board.Position;
const Color = board.Color;

const generate_moves = @import("movegen.zig").generate_moves;

const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");

const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

const perft = @import("perft.zig").perft;

const bitops = @import("bitops.zig");

const zobrist = @import("zobrist.zig");

pub fn init() !void {
    bitboard.init_magics();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
    zobrist.init();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    try init();

    // will probably be overwritten by "ucinewgame" but it prevents undefined behaviour
    // to just define a default position
    var active_color = Color.white;
    var position = Position.initial();
    mainloop: while (true) {
        const command = try uci.next_command(allocator);
        try switch (command) {
            GuiCommand.uci => {
                try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Kaola" } }, allocator);
                try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } }, allocator);
                try send_command(EngineCommand{ .option = .{ .name = "Hash", .option_type = "spin", .default = "4096" } }, allocator);
                try send_command(EngineCommand.uciok, allocator);
            },
            GuiCommand.isready => send_command(EngineCommand.readyok, allocator),
            GuiCommand.debug => {},
            GuiCommand.newgame => position = Position.initial(),
            GuiCommand.position => |new_position| position = new_position,
            GuiCommand.go => {
                const best_move = try searcher.search(position, 4, allocator);
                try send_command(EngineCommand{ .bestmove = best_move }, allocator);
            },
            GuiCommand.stop => {},
            GuiCommand.board => {
                const stdout = std.io.getStdOut().writer();
                try position.print(stdout);
            },
            GuiCommand.eval => {
                switch (active_color) {
                    Color.white => std.debug.print("{d} (from white's perspective)\n", .{pesto.evaluate(Color.white, position)}),
                    Color.black => std.debug.print("{d} (from black's perspective)\n", .{pesto.evaluate(Color.black, position)}),
                }
            },
            GuiCommand.moves => {
                var move_list = ArrayList(Move).init(allocator);
                defer move_list.deinit();

                switch (position.active_color) {
                    Color.white => try generate_moves(Color.white, position, &move_list),
                    Color.black => try generate_moves(Color.black, position, &move_list),
                }

                for (move_list.items) |move| {
                    const move_name = try move.to_str(allocator);
                    std.debug.print("{s}\n", .{move_name});
                    allocator.free(move_name);
                }
            },
            GuiCommand.perft => |depth| {
                const report = try perft(position, allocator, @intCast(u8, depth));
                try send_command(EngineCommand{ .report_perft = report }, allocator);
            },
            GuiCommand.quit => break :mainloop,
        };
    }
}

// Uncommenting this causes an ICE, wait until https://github.com/ziglang/zig/issues/12935 is closed
// pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
//     @setCold(true);
//     const stderr = std.io.getStdErr().writer();
//     stderr.print("The engine panicked, this is a bug.\nPlease file an issue at https://github.com/Wuelle/zigchess, including the debug information below.\nThanks ^_^\n", .{}) catch std.os.abort();
//     std.debug.panicImpl(trace, @returnAddress(), msg);
// }

test {
    try init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
