const std = @import("std");
const ArrayList = std.ArrayList;
const Level = std.log.Level;
const Scope = std.log.default;

const bitboard = @import("bitboard.zig");

const board = @import("board.zig");
const Move = board.Move;
const GameState = board.GameState;
const Color = board.Color;

const generate_moves = @import("movegen.zig").generate_moves;

const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");

const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

const LOG_FILE = "logs";

pub fn init() !void {
    std.fs.cwd().deleteFile(LOG_FILE) catch {}; // if the file doesn't exist, thats fine
    _ = try std.fs.cwd().createFile(LOG_FILE, .{});
    // bitboard.init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
}

pub fn log(comptime message_level: Level, comptime scope: anytype, comptime format: []const u8, args: anytype) void {
    _ = scope;
    _ = message_level;
    const file = std.fs.cwd().openFile(LOG_FILE, .{.write = true}) catch unreachable;
    file.seekFromEnd(0) catch unreachable;
    _ = std.fmt.format(file.writer(), format, args) catch unreachable;
    file.close();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    try init();

    // will probably be overwritten by "ucinewgame" but it prevents undefined behaviour
    // just define a default position
    var active_color = Color.white;
    var state = GameState.initial();
    mainloop: while (true) {
        const command = try uci.next_command(allocator);
        try switch (command) {
            GuiCommand.uci => {
                try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Mephisto" } }, allocator);
                try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } }, allocator);
                try send_command(EngineCommand.uciok, allocator);
            },
            GuiCommand.isready => send_command(EngineCommand.readyok, allocator),
            GuiCommand.debug => {},
            GuiCommand.newgame => {
                active_color = Color.white;
                state = GameState.initial();
            },
            GuiCommand.position => |game| {
                active_color = game.active_color;
                state = game.state;
            },
            GuiCommand.go => {
                const best_move = try searcher.search(active_color, state, 3, allocator);
                try send_command(EngineCommand{ .bestmove = best_move }, allocator);
            },
            GuiCommand.stop => {},
            GuiCommand.board => state.print(),
            GuiCommand.eval => {
                switch (active_color) {
                    Color.white => std.debug.print("{d}\n", .{pesto.evaluate(Color.white, state.position)}),
                    Color.black => std.debug.print("{d}\n", .{pesto.evaluate(Color.black, state.position)}),
                }
            },
            GuiCommand.moves => {
                var move_list = ArrayList(Move).init(allocator);
                defer move_list.deinit();

                switch (active_color) {
                    Color.white => try generate_moves(Color.white, state, &move_list),
                    Color.black => try generate_moves(Color.black, state, &move_list),
                }
                

                for (move_list.items) |move| {
                    const move_name = try move.to_str(allocator);
                    std.debug.print("{s}\n", .{move_name});
                    allocator.free(move_name);
                }
            },
            GuiCommand.quit => break :mainloop,
        };
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    const stderr = std.io.getStdErr().writer();
    stderr.print("The engine panicked, this is a bug.\nPlease file an issue at https://github.com/Wuelle/zigchess, including the debug information below.\nThanks ^_^\n", .{}) catch std.os.abort();
    const first_trace_addr = @returnAddress();
    std.debug.panicImpl(error_return_trace, first_trace_addr, msg);
}

test {
    try init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
