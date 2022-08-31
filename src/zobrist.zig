//! Zobrist hashing
const board = @import("board.zig");
const Rand64 = @import("rand.zig").Rand64;

var rand64 = Rand64.new();
const piece_tables: [12][64]u64 = init_piece_tables();
const castle_tables: [4]u64 = [4]u64{ rand64.next(), rand64.next(), rand64.next(), rand64.next() };
const en_passant_tables = [8]u64{
    rand64.next(),
    rand64.next(),
    rand64.next(),
    rand64.next(),
    rand64.next(),
    rand64.next(),
    rand64.next(),
    rand64.next(),
};
const white_to_move = rand64.next();

fn init_piece_tables() [12][64]u64 {
    var tables: [12][64]u64 = undefined;
    var piece: u4 = 0;
    while (piece < 12) : (piece += 1) {
        var square: u7 = 0;
        while (square < 64) : (square += 1) {
            tables[piece][square] = rand64.next();
        }
    }
    return tables;
}

/// Fully hash the board state.
/// This method should only called once - once an initial hash has been acquired, it
/// can be mutated move by move *without* needing to redo the entire process.
fn full_hash(game: board.Board) u64 {
    var hash: u64 = 0;
    var square: u7 = 0;
    while (square < 64) : (square += 1) {
        if (game.pieces[square]) |piece| {
            hash ^= piece_tables[@enumToInt(piece)];
        }
    }
    if (game.active_color == board.Color.white) {
        hash ^= white_to_move;
    }
    return hash;
}
