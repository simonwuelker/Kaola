const std = @import("std");
const bitboard = @import("bitboard.zig");
const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");
const pesto = @import("pesto.zig");
const searcher = @import("searcher.zig");
const uci = @import("uci.zig");

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
        switch (command) {
            uci.Command.quit => break :mainloop,
            uci.Command.newgame => game = Board.starting_position(),
            uci.Command.go => {},
            uci.Command.stop => {},
            uci.Command.board => game.print(),
            uci.Command.eval => std.debug.print("{d}\n", .{pesto.evaluate(game)}),
        }
    }
    // var game = try board.Board.from_fen("8/7q/8/8/4Q3/8/P1K5/8 w - - 99 50");
    // var game = board.Board.starting_position();
    // game.print();
    // std.debug.print("eval says {d}\n", .{pesto.evaluate(game)});
    // game.apply(searcher.search(game));
    // game.print();
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
