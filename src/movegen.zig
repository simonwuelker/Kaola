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
};

pub const MoveCallback = fn (move: Move) void;

const Pinmask = struct {
    straight: u64,
    diagonal: u64,
    both: u64,
};

pub fn generate_pinmask(game: board.Board, us: u2, them: u2) Pinmask {
    const king_square = @truncate(u6, @ctz(u64, game.position[us][board.KING]));

    // diagonal pins
    const diag_attackers = game.position[them][board.BISHOP] | game.position[them][board.QUEEN];
    const diag_blockers = bitboard.bishop_attacks(king_square, game.occupancies[board.BOTH]) & game.occupancies[us];
    const diag_xray_attacks = bitboard.bishop_attacks(king_square, game.occupancies[board.BOTH] ^ diag_blockers);
    var diag_pinners: u64 = diag_xray_attacks & diag_attackers;
    var diag_pinmask: u64 = diag_pinners; // capturing the pinning piece is valid
    while (diag_pinners != 0) : (bitops.pop_ls1b(&diag_pinners)) {
        const pinner_square = @truncate(u6, @ctz(u64, diag_pinners));
        diag_pinmask |= diag_xray_attacks & bitboard.bishop_attacks(pinner_square, game.position[us][board.KING]);
    }

    // straight pins
    const straight_attackers = game.position[them][board.ROOK] | game.position[them][board.QUEEN];
    const straight_blockers = bitboard.rook_attacks(king_square, game.occupancies[board.BOTH]) & game.occupancies[us];
    const straight_xray_attacks = bitboard.rook_attacks(king_square, game.occupancies[board.BOTH] ^ straight_blockers);
    var straight_pinners: u64 = straight_xray_attacks & straight_attackers;
    var straight_pinmask: u64 = straight_pinners; // capturing the pinning piece is valid
    while (straight_pinners != 0) : (bitops.pop_ls1b(&straight_pinners)) {
        const pinner_square = @truncate(u6, @ctz(u64, straight_pinners));
        straight_pinmask |= straight_xray_attacks & bitboard.rook_attacks(pinner_square, game.position[us][board.KING]);
    }

    return Pinmask{
        .straight = straight_pinmask,
        .diagonal = diag_pinmask,
        .both = straight_pinmask | diag_pinmask,
    };
}

/// The checkmask will be:
/// * All bits set if our king is not currently in check
/// * The bits on the path to the checking piece set if the king is in a single check
/// * No bits set if two pieces are attacking the king
/// That way, legal non-king moves can be masked. (Because they either have to block the check or 
/// capture the attacking piece)
pub fn generate_checkmask(game: board.Board) u64 {
    const us: u2 = if (game.white_to_move) board.WHITE else board.BLACK;
    const them: u2 = if (!game.white_to_move) board.WHITE else board.BLACK;
    const opponent_straight_sliders: u64 = game.position[them][board.ROOK] | game.position[them][board.QUEEN];
    const opponent_diag_sliders: u64 = game.position[them][board.BISHOP] | game.position[them][board.QUEEN];
    const king_square = @truncate(u6, @ctz(u64, game.position[us][board.KING]));

    var checkmask: u64 = 0;
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

    const attacking_knight = bitboard.knight_attack(king_square) & game.position[them][board.KNIGHT];
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

pub fn generate_moves(game: board.Board, callback: MoveCallback) void {
    const us: u2 = if (game.white_to_move) board.WHITE else board.BLACK;
    const them: u2 = if (!game.white_to_move) board.WHITE else board.BLACK;
    const enemy_or_empty = ~game.occupancies[us];
    const checkmask = generate_checkmask(game);
    const pinmask = generate_pinmask(game, us, them);

    // legal knight moves
    // pinned knights can never move
    var unpinned_knights = game.position[us][board.KNIGHT] & ~pinmask.both;
    while (unpinned_knights != 0) : (bitops.pop_ls1b(&unpinned_knights)) {
        const square = @truncate(u6, @ctz(u64, unpinned_knights));
        var knight_moves = bitboard.knight_attack(square) & enemy_or_empty & checkmask;
        while (knight_moves != 0) : (bitops.pop_ls1b(&knight_moves)) {
            const to = @truncate(u6, @ctz(u64, knight_moves));
            callback(Move{
                .from = square,
                .to = to,
            });
        }
    }

    // legal bishop moves
    // straight pinned bishops can never move
    // const unpinned_bishops = game.position[us][board.BISHOP] & ~pinmask.both;
    // const unp_bishop_moves = bitboard.bishop_attacks(unpinned_bishops, game.occupancies[board.BOTH]);
    // const pinned_bishops = game.position[us][board.BISHOP] & pinmask.diagonal;
    // const pin_bishop_moves = bitboard.bishop_attacks(pinned_bishops, game.occupancies[board.BOTH]) & pinmask.diagonal;
    // bitboard.print_bitboard(unp_bishop_moves | pin_bishop_moves, "knight moves");
}

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
