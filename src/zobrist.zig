//! Zobrist hashing
const board = @import("board.zig");
const Color = board.Color;
const Piece = board.Piece;
const Square = board.Square;
const SquareIterator = board.SquareIterator;
const Rand64 = @import("rand.zig").Rand64;

var piece_tables: [12][64]u64 = undefined;
var castle_table: [4]u64 = undefined;
var en_passant_table: [8]u64 = undefined;
pub var color_hash: u64 = undefined;

pub fn init() void {
    var rand64 = Rand64.new();

    color_hash = rand64.next();

    castle_table[0] = rand64.next();
    castle_table[1] = rand64.next();
    castle_table[2] = rand64.next();
    castle_table[3] = rand64.next();

    en_passant_table[0] = rand64.next();
    en_passant_table[1] = rand64.next();
    en_passant_table[2] = rand64.next();
    en_passant_table[3] = rand64.next();
    en_passant_table[4] = rand64.next();
    en_passant_table[5] = rand64.next();
    en_passant_table[6] = rand64.next();
    en_passant_table[7] = rand64.next();

    var piece: u4 = 0;
    while (piece < 12) : (piece += 1) {
        var squares = SquareIterator.new();
        while (squares.next()) |square| {
            piece_tables[piece][@enumToInt(square)] = rand64.next();
        }
    }
}

pub fn piece_hash(piece: Piece, square: Square) u64 {
    switch (piece.color()) {
        Color.white => return piece_tables[@enumToInt(piece)][@enumToInt(square)],
        Color.black => return piece_tables[@enumToInt(piece) - 2][@enumToInt(square)],
    }
}
