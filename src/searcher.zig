//! (For now) a very primitive search
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Color = @import("board.zig").Color;
const movegen = @import("movegen.zig");
const generate_moves = movegen.generate_moves;
const pesto = @import("pesto.zig");

const board = @import("board.zig");
const Position = board.Position;
const Move = board.Move;

const MIN_SCORE = -1000000;
const MAX_SCORE = 1000000;

pub fn search(position: Position, comptime depth: u8, allocator: Allocator) !Move {
    switch (position.active_color) {
        Color.white => return try alpha_beta_search(Color.white, depth, position, allocator),
        Color.black => return try alpha_beta_search(Color.black, depth, position, allocator),
    }
}

fn alpha_beta_search(comptime active_color: Color, comptime depth: u8, position_: Position, allocator: Allocator) Allocator.Error!Move {
    var position = position_;
    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    try generate_moves(active_color, position, &move_list);

    var best_move: Move = undefined;
    var best_score: i32 = undefined;
    var found_a_move = false;

    for (move_list.items) |move_to_consider| {
        position.make_move(active_color, move_to_consider);
        defer position.undo_move(move_to_consider);
        const score = try min_value(active_color.other(), depth - 1, position, allocator, MIN_SCORE, MAX_SCORE);

        if (score > best_score or !found_a_move) {
            best_move = move_to_consider;
            best_score = score;
            found_a_move = true;
        }
    }
    std.debug.assert(found_a_move); // this would actually not be the engines fault as its stalemate/checkmate
    return best_move;
}

fn max_value(comptime active_color: Color, comptime depth: u8, position_: Position, allocator: Allocator, alpha_: i32, beta_: i32) Allocator.Error!i32 {
    var position = position_;
    if (depth == 0) {
        return pesto.evaluate(active_color, position);
    } else {
        var alpha: i32 = alpha_;
        var beta: i32 = beta_;

        var move_list = try ArrayList(Move).initCapacity(allocator, 48);
        defer move_list.deinit();

        var score: i32 = MIN_SCORE;
        try generate_moves(active_color, position, &move_list);
        for (move_list.items) |move_to_consider| {
            position.make_move(active_color, move_to_consider);
            defer position.undo_move(move_to_consider);

            score = @max(score, try min_value(active_color.other(), depth - 1, position, allocator, alpha, beta));

            if (score >= beta) {
                return score;
            }
            alpha = @max(score, alpha);
        }

        return score;
    }
}

fn min_value(comptime active_color: Color, comptime depth: u8, position_: Position, allocator: Allocator, alpha_: i32, beta_: i32) Allocator.Error!i32 {
    var position = position_;
    if (depth == 0) {
        return pesto.evaluate(active_color.other(), position);
    } else {
        var alpha: i32 = alpha_;
        var beta: i32 = beta_;

        var move_list = try ArrayList(Move).initCapacity(allocator, 48);
        defer move_list.deinit();

        var score: i32 = MAX_SCORE;
        try generate_moves(active_color, position, &move_list);
        for (move_list.items) |move_to_consider| {
            position.make_move(active_color, move_to_consider);
            defer position.undo_move(move_to_consider);

            score = @min(score, try max_value(active_color.other(), depth - 1, position, allocator, alpha, beta));

            if (score <= alpha) {
                return score;
            }
            beta = @min(score, beta);
        }

        return score;
    }
}
