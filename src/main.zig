const std = @import("std");
const bitboard = @import("bitboard.zig");
const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");

const Field = enum(u6) {
    A8, B8, C8, D8, E8, F8, G8, H8,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A1, B1, C1, D1, E1, F1, G1, H1,
};


pub fn init() void {
    // init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
}

pub fn main() !void {
    init();
    // bitboard.print_bitboard(bitboard.PATH_BETWEEN_SQUARES[@enumToInt(Field.B3)][@enumToInt(Field.G8)]);
    var board = try Board.from_fen("8/8/5q2/8/8/2K5/8/8 w - - 99 50");
    bitboard.print_bitboard(movegen.generate_checkmask(board));
    // const bb = board.attacked_squares(true);
    // board.print();
    // bitboard.print_bitboard(bb);
    // movegen.generate_moves(board);
}
