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
    switch (position.active_color) {
        Color.white => {
            return perft_entry(Color.white, position, allocator, depth);
        },
        Color.black => {
            return perft_entry(Color.black, position, allocator, depth);
        },
    }
}

fn perft_entry(comptime color: Color, position: Position, allocator: Allocator, depth: u8) !PerftResult {
    const start = try Instant.now();
    var nodes: u64 = 0;

    switch (depth) {
        1 => try perft_recursive(color, 1, position, allocator, &nodes),
        2 => try perft_recursive(color, 2, position, allocator, &nodes),
        3 => try perft_recursive(color, 3, position, allocator, &nodes),
        4 => try perft_recursive(color, 4, position, allocator, &nodes),
        5 => try perft_recursive(color, 5, position, allocator, &nodes),
        6 => try perft_recursive(color, 6, position, allocator, &nodes),
        7 => try perft_recursive(color, 7, position, allocator, &nodes),
        8 => try perft_recursive(color, 8, position, allocator, &nodes),
        9 => try perft_recursive(color, 9, position, allocator, &nodes),
        else => std.debug.print("Too deep.\n", .{}),
    }

    const now = try Instant.now();
    return PerftResult{
        .time_elapsed = now.since(start),
        .nodes = nodes,
    };
}

fn perft_recursive(comptime active_color: Color, comptime depth: u8, _position: Position, allocator: Allocator, nodes: *u64) Allocator.Error!void {
    if (depth == 0) {
        // count leaf nodes
        nodes.* += 1;
        return;
    } else {
        var position = _position;

        var move_list = try ArrayList(Move).initCapacity(allocator, 48);
        defer move_list.deinit();

        try generate_moves(active_color, position, &move_list);

        for (move_list.items) |move| {
            position.make_move(active_color, move);
            defer position.undo_move(move);

            try perft_recursive(active_color.other(), depth - 1, position, allocator, nodes);
        }
    }
}
