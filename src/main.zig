const std = @import("std");
const bitboard = @import("bitboard.zig");
const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");
const pesto = @import("pesto.zig");
const searcher = @import("searcher.zig");
const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

pub fn init() void {
    // init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
}

pub fn main() !void {
    init();

    var game: Board = undefined;
    mainloop: while (true) {
        const command = try uci.next_command();
        try switch (command) {
            GuiCommand.uci => {
                try send_command(EngineCommand{ .id = .{ .key = "name", .value = "zigchess" } });
                try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } });
                try send_command(EngineCommand.uciok);
            },
            GuiCommand.isready => send_command(EngineCommand.readyok),
            GuiCommand.debug => {},
            GuiCommand.quit => break :mainloop,
            GuiCommand.newgame => game = Board.starting_position(),
            GuiCommand.go => {
                // const best_move = searcher.search(game, 3);
            },
            GuiCommand.stop => {},
            GuiCommand.board => game.print(),
            GuiCommand.eval => std.debug.print("{d}\n", .{pesto.evaluate(game)}),
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
    init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
