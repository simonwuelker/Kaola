const std = @import("std");
const bitops = @import("bitops.zig");
const board = @import("board.zig");
const bitboardops = @import("bitboardops.zig");

/// Bit mask for masking off the fourth rank
const RANK_4: u64 = 0x000000FF00000000;
/// Bit mask for masking off the fifth rank
const RANK_5: u64 = 0x00000000FF000000;

/// Bitmask for detecting pieces that block white from queenside castling
const WHITE_QUEENSIDE_BLOCKERS = 0xe00000000000000;
/// Bitmask for detecting pieces that block white from kingside castling
const WHITE_KINGSIDE_BLOCKERS = 0x6000000000000000;
/// Bitmask for detecting pieces that block black from queenside castling
const BLACK_QUEENSIDE_BLOCKERS = 0xe;
/// Bitmask for detecting pieces that block black from kingside castling
const BLACK_KINGSIDE_BLOCKERS = 0x60;

/// Different pieces that a pawn can be promoted to once it reaches the opposite side
pub const Promotion = enum {
    Queen,
    Rook,
    Bishop,
    Knight,
};

pub const Move = struct {
    /// Source square
    from: u6,
    /// Target square
    to: u6,
    /// If the move is a promotion: what the pawn promotes into, empty otherwise
    promotion: ?Promotion,
};

fn handle_pawn_promotions(white: bool, source: u6, target: u6) void {
    if (white) {
        if (target < 8) {
            // handle promotions
            std.debug.print("{s} to {s} queen\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} rook\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} bishop\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} knight\n", .{board.square_name(source), board.square_name(target)});
        } else {
            std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
        }
    } else {
        if (target > 55) {
            // handle promotions
            std.debug.print("{s} to {s} queen\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} rook\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} bishop\n", .{board.square_name(source), board.square_name(target)});
            std.debug.print("{s} to {s} knight\n", .{board.square_name(source), board.square_name(target)});
        } else {
            std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
        }
    }
}

pub fn generate_moves(state: board.Board) void {
    const empty = ~state.occupancies[board.BOTH];
    if (state.white_to_move) {
        // quiet pawn moves (single)
        const pawns = state.position[board.WHITE][board.PAWN];
        const pawn_targets: u64 = pawns >> 8 & empty;
        var moves = pawn_targets;
        // iterate over the set bits (=> moves)
        while(moves != 0): (bitops.pop_ls1b(&moves)) {
            const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
            const source: u6 = target + 8;
            handle_pawn_promotions(true, source, target);
        }

        // double pawn moves
        var double_pawn_moves = pawn_targets >> 8 & empty & RANK_4;
        moves = double_pawn_moves;
        // iterate over the set bits (=> moves)
        while(moves != 0): (bitops.pop_ls1b(&moves)) {
            const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
            const source: u6 = target + 16;
            std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
        }

        // pawn captures
        var left_attacks = bitboardops.white_pawn_attacks_left(pawns) & state.occupancies[board.BLACK];
        while (left_attacks != 0): (bitops.pop_ls1b(&left_attacks)) {
            const target = @intCast(u6, bitops.ls1b_index(left_attacks));
            const source = target + 9;
            handle_pawn_promotions(true, source, target);
        }

        var right_attacks = bitboardops.white_pawn_attacks_right(pawns) & state.occupancies[board.BLACK];
        while (right_attacks != 0): (bitops.pop_ls1b(&right_attacks)) {
            const target = @intCast(u6, bitops.ls1b_index(right_attacks));
            const source = target + 7;
            handle_pawn_promotions(true, source, target);
        }

        // castle 
        if (state.castling_rights & board.WHITE_QUEENSIDE != 0 and state.occupancies[board.BOTH] & WHITE_QUEENSIDE_BLOCKERS == 0) {
            std.debug.print("castle long\n", .{});
        }
        if (state.castling_rights & board.WHITE_KINGSIDE != 0 and state.occupancies[board.BOTH] & WHITE_KINGSIDE_BLOCKERS == 0) {
            std.debug.print("castle short\n", .{});
        }
    } else {
        // quiet pawn moves (single)
        const pawns = state.position[board.BLACK][board.PAWN];
        const pawn_targets: u64 = pawns << 8 & empty;
        var moves = pawn_targets;
        // iterate over the set bits (=> moves)
        while(moves != 0): (bitops.pop_ls1b(&moves)) {
            const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
            const source: u6 = target - 8;
            handle_pawn_promotions(false, source, target);
        }

        // double pawn moves
        var double_pawn_moves = pawn_targets << 8 & empty & RANK_5;
        moves = double_pawn_moves;
        // iterate over the set bits (=> moves)
        while(moves != 0): (bitops.pop_ls1b(&moves)) {
            const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
            const source: u6 = target - 16;
            std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
        }

        // pawn captures
        var left_attacks = bitboardops.black_pawn_attacks_left(pawns) & state.occupancies[board.WHITE];
        while (left_attacks != 0): (bitops.pop_ls1b(&left_attacks)) {
            const target = @intCast(u6, bitops.ls1b_index(left_attacks));
            const source = target - 7;
            handle_pawn_promotions(false, source, target);
        }

        var right_attacks = bitboardops.black_pawn_attacks_right(pawns) & state.occupancies[board.WHITE];
        while (right_attacks != 0): (bitops.pop_ls1b(&right_attacks)) {
            const target = @intCast(u6, bitops.ls1b_index(right_attacks));
            const source = target - 9;
            handle_pawn_promotions(false, source, target);
        }

        // castle 
        if (state.castling_rights & board.BLACK_QUEENSIDE != 0 and state.occupancies[board.BOTH] & BLACK_QUEENSIDE_BLOCKERS == 0) {
            std.debug.print("castle long\n", .{});
        }
        if (state.castling_rights & board.BLACK_KINGSIDE != 0 and state.occupancies[board.BOTH] & BLACK_KINGSIDE_BLOCKERS == 0) {
            std.debug.print("castle short\n", .{});
        }
    }
}
