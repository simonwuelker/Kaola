//! (For now) a very primitive search
const Board = @import("board.zig").Board;
const movegen = @import("movegen.zig");
const pesto = @import("pesto.zig");
const Move = movegen.Move;

var moves: [64]Move = undefined;
var num_moves = undefined;

// ultimately, i want to do the alpha-beta search *in here*
// so we can evaluate moves *while* we generate them
// and stop generation as soon as a branch is pruned
fn callback(move: Move) void {
    moves[num_moves] = move;
    num_moves += 1;
}

/// Determines the max score that can be reached in a given position using alpha-beta search
fn max_score(board: Board, depth: u8) i16 {
    if (depth == 0) return pesto.evaluate(board);
    num_moves = 0;
    var best_score = -100; // something low, idk
    movegen.generate_moves(board, callback);
    for (moves[0..num_moves]) |move| {
        var modified = board;
        modified.apply(move);
        const score = max_score(modified, depth - 1);
        best_score = @maximum(score, best_score);
    }
    return best_score;
}

pub fn search(board: Board, depth: u8) Move {
    num_moves = 0;
    movegen.generate_moves(board, callback);
    var best_move = undefined;
    var best_score = -100;
    for (moves[0..num_moves]) |move| {
        var modified = board;
        modified.apply(move);
        const score = max_score(modified, depth - 1);
        if (best_score < score) {
            best_move = move;
            best_score = score;
        }
    }
    return best_move;
}
