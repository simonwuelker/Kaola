const std = @import("std");
const bitboard = @import("bitboard.zig");
const board = @import("board.zig");
const movegen = @import("movegen.zig");

pub fn init() void {
    // init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
}

fn callback(move: movegen.Move) void {
    std.debug.print("{s} to {s}\n", .{ board.square_name(move.from), board.square_name(move.to) });
}

pub fn main() !void {
    init();

    var game = try board.Board.from_fen("8/7q/8/8/4Q3/8/P1K5/8 w - - 99 50");
    game.print();
    // const bb = board.attacked_squares(true);
    // board.print();
    // bitboard.print_bitboard(bb);
    movegen.generate_moves(game, callback);
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
