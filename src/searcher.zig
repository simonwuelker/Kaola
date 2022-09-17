//! (For now) a very primitive search
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Color = @import("board.zig").Color;
const movegen = @import("movegen.zig");
const generate_moves = movegen.generate_moves;
const pesto = @import("pesto.zig");

const board = @import("board.zig");
const GameState = board.GameState;
const Move = board.Move;

const MIN_SCORE = -1000;
const MAX_SCORE = 1000;

pub fn search(active_color: Color, state: GameState, depth: u8, allocator: Allocator) !Move {
    switch (active_color) {
        Color.white => return try alpha_beta_search(Color.white, state, depth, allocator),
        Color.black => return try alpha_beta_search(Color.black, state, depth, allocator),
    }
}

fn alpha_beta_search(comptime active_color: Color, state: GameState, depth: u8, allocator: Allocator) Allocator.Error!Move {
    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    try generate_moves(active_color, state, &move_list);

    var best_move: Move = undefined;
    var best_score: i16 = MIN_SCORE;

    for (move_list.items) |move_to_consider| {
        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        const score = try max_value(new_color, new_state, depth - 1, allocator, MIN_SCORE, MAX_SCORE);

        if (score > best_score) {
            best_move = move_to_consider;
            best_score = score;
        }
    }
    return best_move;
}

fn max_value(comptime active_color: Color, state: GameState, depth: u8, allocator: Allocator, alpha_: i16, beta_: i16) Allocator.Error!i16 {
    if (depth == 0) {
        return pesto.evaluate(active_color, state.position);
    }
    var alpha: i16 = alpha_;
    var beta: i16 = beta_;

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    var score: i16 = MIN_SCORE;
    try generate_moves(active_color, state, &move_list);
    for (move_list.items) |move_to_consider| {
        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        score = @maximum(score, try min_value(new_color, new_state, depth - 1, allocator, alpha, beta));

        if (score >= beta) {
            return score;
        }
        alpha = @maximum(score, alpha);
    }

    return score;

}

fn min_value(comptime active_color: Color, state: GameState, depth: u8, allocator: Allocator, alpha_: i16, beta_: i16) Allocator.Error!i16 {
    if (depth == 0) {
        return pesto.evaluate(active_color, state.position);
    }
    var alpha: i16 = alpha_;
    var beta: i16 = beta_;

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    var score: i16 = MAX_SCORE;
    try generate_moves(active_color, state, &move_list);
    for (move_list.items) |move_to_consider| {
        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        score = @minimum(score, try max_value(new_color, new_state, depth - 1, allocator, alpha, beta));

        if (score <= alpha) {
            return score;
        }
        beta = @minimum(score, beta);
    }

    return score;
}
