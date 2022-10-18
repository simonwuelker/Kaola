const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Instant = std.time.Instant;

const board = @import("board.zig");
const Move = board.Move;
const Position = board.Position;
const Color = board.Color;

const generate_moves = @import("movegen.zig").generate_moves;

pub const PerftResult = struct {
    time_elapsed: u64,
    nodes: u64,
};

pub fn perft(position: Position, allocator: Allocator, depth: u8) !PerftResult {
    const start = try Instant.now();
    var nodes: u64 = 0;

    switch (position.active_color) {
        Color.white => {
            try perft_recursive(Color.white, position, allocator, &nodes, depth);
        },
        Color.black => {
            try perft_recursive(Color.black, position, allocator, &nodes, depth);
        },
    }

    const now = try Instant.now();
    return PerftResult{
        .time_elapsed = now.since(start),
        .nodes = nodes,
    };
}

fn perft_recursive(comptime active_color: Color, _position: Position, allocator: Allocator, nodes: *u64, depth: u8) Allocator.Error!void {
    if (depth == 0) {
        nodes.* += 1;
        return;
    }
    var position = _position;

    var move_list = ArrayList(Move).init(allocator);
    defer move_list.deinit();

    try generate_moves(active_color, position, &move_list);

    for (move_list.items) |move| {
        position.make_move(active_color, move);
        defer position.undo_move(move);

        try perft_recursive(active_color.other(), position, allocator, nodes, depth - 1);
    }
}
