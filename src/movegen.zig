//! Generates legal chess moves in a given position
const std = @import("std");
const bitops = @import("bitops.zig");
const board = @import("board.zig");
const bitboard = @import("bitboard.zig");

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


/// The checkmask will be:
/// * All bits set if our king is not currently in check
/// * The bits on the path to the checking piece set if the king is in a single check
/// * No bits set if two pieces are attacking the king
/// That way, legal non-king moves can be masked. (Because they either have to block the check or 
/// capture the attacking piece)
pub fn generate_checkmask(game: board.Board) u64 {
    const us: u2 = if (game.white_to_move) board.WHITE else board.BLACK;
    const them: u2  = if (!game.white_to_move) board.WHITE else board.BLACK;
    const opponent_straight_sliders: u64 = game.position[them][board.ROOK] | game.position[them][board.QUEEN];
    const opponent_diag_sliders: u64 = game.position[them][board.BISHOP] | game.position[them][board.QUEEN];
    const king_square = @truncate(u6, @ctz(u64, game.position[us][board.KING]));

    var checkmask: u64  = 0;
    var in_check: bool = false;

    // there can at most be one diag slider attacking the king (even with promotions, i think)
    const attacking_diag_slider = bitboard.bishop_attacks(king_square, game.occupancies[board.BOTH]) & opponent_diag_sliders;
    if (attacking_diag_slider != 0) {
        const attacker_square = @truncate(u6, @ctz(u64, attacking_diag_slider));
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[attacker_square][king_square];
        in_check = true;
    }

    const attacking_straight_slider = bitboard.rook_attacks(king_square, game.occupancies[board.BOTH]) & opponent_straight_sliders;
    if (attacking_straight_slider != 0) {
        const attacker_square = @truncate(u6, @ctz(u64, attacking_straight_slider));
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[attacker_square][king_square];
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_knight = bitboard.single_knight_attack(king_square) & game.position[them][board.KNIGHT];
    if (attacking_knight != 0) {
        const knight_square = @truncate(u6, @ctz(u64, attacking_knight));
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[knight_square][king_square];
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_pawns = switch (us) {
        board.WHITE => bitboard.white_pawn_attacks(game.position[us][board.KING]) & game.position[them][board.PAWN],
        board.BLACK => bitboard.black_pawn_attacks(game.position[us][board.KING]) & game.position[them][board.PAWN],
        else => unreachable,
    };
    if (attacking_pawns != 0) {
        const pawn_square = @truncate(u6, @ctz(u64, attacking_pawns));
        checkmask |= @as(u64, 1) << pawn_square;
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }
    
    if (in_check) return checkmask;
    return ~@as(u64, 0);

}

// pub fn generate_moves(state: board.Board) void {
//     // Find the possible king moves
//     const color = if (state.white_to_move) board.WHITE else board.BLACK;
//     const opponent  = if (!state.white_to_move) board.WHITE else board.BLACK;
//     // const unsafe_squares = state.king_unsafe_squares();
// 
//     // king can move to any square that isn't attacked or occupied by our own piece
//     // const possible_king_moves = bitboard.king_attacks(state.position[color][board.KING] & (~unsafe_squares | state.occupancy[color]));
//     // const quiet_king_moves = possible_king_moves & ~state.occupancy[opponent];
//     // const capture_king_moves = possible_king_moves & state.occupancy[opponent];
// 
//     const empty = ~state.occupancies[board.BOTH];
//     if (state.white_to_move) {
//         // quiet pawn moves (single)
//         const pawns = state.position[board.WHITE][board.PAWN];
//         const pawn_targets: u64 = pawns >> 8 & empty;
//         var moves = pawn_targets;
//         // iterate over the set bits (=> moves)
//         while(moves != 0): (bitops.pop_ls1b(&moves)) {
//             const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
//             const source: u6 = target + 8;
//             handle_pawn_promotions(true, source, target);
//         }
// 
//         // double pawn moves
//         var double_pawn_moves = pawn_targets >> 8 & empty & RANK_4;
//         moves = double_pawn_moves;
//         // iterate over the set bits (=> moves)
//         while(moves != 0): (bitops.pop_ls1b(&moves)) {
//             const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
//             const source: u6 = target + 16;
//             std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
//         }
// 
//         // pawn captures
//         var left_attacks = bitboard.white_pawn_attacks_left(pawns) & state.occupancies[board.BLACK];
//         while (left_attacks != 0): (bitops.pop_ls1b(&left_attacks)) {
//             const target = @intCast(u6, bitops.ls1b_index(left_attacks));
//             const source = target + 9;
//             handle_pawn_promotions(true, source, target);
//         }
// 
//         var right_attacks = bitboard.white_pawn_attacks_right(pawns) & state.occupancies[board.BLACK];
//         while (right_attacks != 0): (bitops.pop_ls1b(&right_attacks)) {
//             const target = @intCast(u6, bitops.ls1b_index(right_attacks));
//             const source = target + 7;
//             handle_pawn_promotions(true, source, target);
//         }
// 
//         // castle 
//         if (state.castling_rights & board.WHITE_QUEENSIDE != 0 and state.occupancies[board.BOTH] & WHITE_QUEENSIDE_BLOCKERS == 0) {
//             std.debug.print("castle long\n", .{});
//         }
//         if (state.castling_rights & board.WHITE_KINGSIDE != 0 and state.occupancies[board.BOTH] & WHITE_KINGSIDE_BLOCKERS == 0) {
//             std.debug.print("castle short\n", .{});
//         }
//     } else {
//         // quiet pawn moves (single)
//         const pawns = state.position[board.BLACK][board.PAWN];
//         const pawn_targets: u64 = pawns << 8 & empty;
//         var moves = pawn_targets;
//         // iterate over the set bits (=> moves)
//         while(moves != 0): (bitops.pop_ls1b(&moves)) {
//             const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
//             const source: u6 = target - 8;
//             handle_pawn_promotions(false, source, target);
//         }
// 
//         // double pawn moves
//         var double_pawn_moves = pawn_targets << 8 & empty & RANK_5;
//         moves = double_pawn_moves;
//         // iterate over the set bits (=> moves)
//         while(moves != 0): (bitops.pop_ls1b(&moves)) {
//             const target: u6 = @intCast(u6, bitops.ls1b_index(moves));
//             const source: u6 = target - 16;
//             std.debug.print("{s} to {s}\n", .{board.square_name(source), board.square_name(target)});
//         }
// 
//         // pawn captures
//         var left_attacks = bitboard.black_pawn_attacks_left(pawns) & state.occupancies[board.WHITE];
//         while (left_attacks != 0): (bitops.pop_ls1b(&left_attacks)) {
//             const target = @intCast(u6, bitops.ls1b_index(left_attacks));
//             const source = target - 7;
//             handle_pawn_promotions(false, source, target);
//         }
// 
//         var right_attacks = bitboard.black_pawn_attacks_right(pawns) & state.occupancies[board.WHITE];
//         while (right_attacks != 0): (bitops.pop_ls1b(&right_attacks)) {
//             const target = @intCast(u6, bitops.ls1b_index(right_attacks));
//             const source = target - 9;
//             handle_pawn_promotions(false, source, target);
//         }
// 
//         // castle 
//         if (state.castling_rights & board.BLACK_QUEENSIDE != 0 and state.occupancies[board.BOTH] & BLACK_QUEENSIDE_BLOCKERS == 0) {
//             std.debug.print("castle long\n", .{});
//         }
//         if (state.castling_rights & board.BLACK_KINGSIDE != 0 and state.occupancies[board.BOTH] & BLACK_KINGSIDE_BLOCKERS == 0) {
//             std.debug.print("castle short\n", .{});
//         }
//     }
// }

test "checkmask generation" {
    const expectEqual = std.testing.expectEqual;

    // Simple check
    const simple = try board.Board.from_fen("8/8/5q2/8/8/2K5/8/8 w - - 0 0");
    std.debug.print("{d}\n", .{@popCount(u64, generate_checkmask(simple))});
    try expectEqual(@as(u7, 3), @popCount(u64, generate_checkmask(simple)));

    // Double check - no moves (except king moves) allowed
    const double = try board.Board.from_fen("8/8/5q2/8/1p6/2K5/8/8 w - - 0 0");
    try expectEqual(@as(u64, 0), generate_checkmask(double));

    // No check
    const no_check = try board.Board.from_fen("8/8/8/3K4/8/8/8/8 w - - 0 0");
    try expectEqual(~@as(u64, 0), generate_checkmask(no_check));
}
