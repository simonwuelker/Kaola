const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Instant = std.time.Instant;

const board = @import("board.zig");
const Move = board.Move;
const GameState = board.GameState;
const Color = board.Color;

const generate_moves = @import("movegen.zig").generate_moves;

pub const PerftResult = struct {
    time_elapsed: u64,
    nodes: u64,
};

pub fn perft(active_color: Color, state: GameState, allocator: Allocator, depth: u8) !PerftResult {
    const start = try Instant.now();
    var nodes: u64 = 0;

    switch (active_color) {
        Color.white => {
            try perft_recursive(Color.white, state, allocator, &nodes, depth);
        },
        Color.black => {
            try perft_recursive(Color.black, state, allocator, &nodes, depth);
        },
    }

    const now = try Instant.now();
    return PerftResult {
        .time_elapsed = now.since(start),
        .nodes = nodes,
    };
}

fn perft_recursive(comptime active_color: Color, state: GameState, allocator: Allocator, nodes: *u64, depth: u8) Allocator.Error!void {
    if (depth == 0) {
        nodes.* += 1;
        return;
    }

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    try generate_moves(active_color, state, &move_list);

    for (move_list.items) |move| {
        const new_state = state.make_move(active_color, move);
        const new_color = comptime active_color.other();
        try perft_recursive(new_color, new_state, allocator, nodes, depth - 1);
    }
}
