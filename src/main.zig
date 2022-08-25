const std = @import("std");
const bitboard = @import("bitboard.zig");
const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");

pub fn init() void {
    // init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
}

pub fn main() !void {
    init();
    // bitboard.print_bitboard(bitboard.PATH_BETWEEN_SQUARES[@enumToInt(Field.B3)][@enumToInt(Field.G8)]);
    var board = try Board.from_fen("8/8/5q2/8/8/2K5/8/8 w - - 99 50");
    board.print();
    bitboard.print_bitboard(movegen.generate_checkmask(board));
    // const bb = board.attacked_squares(true);
    // board.print();
    // bitboard.print_bitboard(bb);
    // movegen.generate_moves(board);
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
