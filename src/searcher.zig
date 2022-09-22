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

const MIN_SCORE = -1000000;
const MAX_SCORE = 1000000;

pub fn search(active_color: Color, state: GameState, depth: u8, allocator: Allocator) !Move {
    switch (active_color) {
        Color.white => return try alpha_beta_search(Color.white, state, depth, allocator),
        Color.black => return try alpha_beta_search(Color.black, state, depth, allocator),
    }
}

fn log_move(move: Move, depth: u8, allocator: Allocator) void {
    _ = move;
    _ = depth;
    _ = allocator;
    // var cnt: u8 = 0;
    // while (cnt < 4 - depth): (cnt += 1) {
    //     std.debug.print(" ", .{});
    // }
    // std.debug.print("({d})", .{depth});
    // const move_name = move.to_str(allocator) catch unreachable;
    // std.debug.print(" {s}\n", .{move_name});
    // allocator.free(move_name);
}

fn alpha_beta_search(comptime active_color: Color, state: GameState, depth: u8, allocator: Allocator) Allocator.Error!Move {
    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    try generate_moves(active_color, state, &move_list);

    var best_move: Move = undefined;
    var best_score: i32 = undefined;
    var found_a_move = false;

    for (move_list.items) |move_to_consider| {
        log_move(move_to_consider, depth, allocator);
        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        const score = try min_value(new_color, active_color, new_state, depth - 1, allocator, MIN_SCORE, MAX_SCORE);
        // std.debug.print("the score is {d}\n", .{score});

        if (score > best_score or !found_a_move) {
            best_move = move_to_consider;
            best_score = score;
            found_a_move = true;
        }
    }
    std.debug.assert(found_a_move); // this would actually not be the engines fault as its stalemate/checkmate
    return best_move;
}

fn max_value(comptime active_color: Color, comptime player: Color, state: GameState, depth: u8, allocator: Allocator, alpha_: i32, beta_: i32) Allocator.Error!i32 {
    if (depth == 0) {
        return pesto.evaluate(player, state.position);
    }
    var alpha: i32 = alpha_;
    var beta: i32 = beta_;

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    var score: i32 = MIN_SCORE;
    try generate_moves(active_color, state, &move_list);
    for (move_list.items) |move_to_consider| {
        log_move(move_to_consider, depth, allocator);

        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        score = @maximum(score, try min_value(new_color, player, new_state, depth - 1, allocator, alpha, beta));

        if (score >= beta) {
            return score;
        }
        alpha = @maximum(score, alpha);
    }

    return score;

}

fn min_value(comptime active_color: Color, comptime player: Color, state: GameState, depth: u8, allocator: Allocator, alpha_: i32, beta_: i32) Allocator.Error!i32 {
    if (depth == 0) {
        return pesto.evaluate(player, state.position);
    }
    var alpha: i32 = alpha_;
    var beta: i32 = beta_;

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    var score: i32 = MAX_SCORE;
    try generate_moves(active_color, state, &move_list);
    for (move_list.items) |move_to_consider| {
        log_move(move_to_consider, depth, allocator);

        const new_state = state.make_move(active_color, move_to_consider);
        const new_color = comptime active_color.other();
        score = @minimum(score, try max_value(new_color, player, new_state, depth - 1, allocator, alpha, beta));

        if (score <= alpha) {
            return score;
        }
        beta = @minimum(score, beta);
    }

    return score;
}
