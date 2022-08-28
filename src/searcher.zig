const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;

var best_move: Move = undefined;
fn callback(move: movegen.Move) void {
    best_move = move; // great eval much wow
}

/// Determines the best move in a given position
pub fn search(board: Board) Move {
    movegen.generate_moves(board, callback);
    return best_move;
}
