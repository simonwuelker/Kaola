//! Generates legal chess moves in a given position
const std = @import("std");
const bitops = @import("bitops.zig");
const board = @import("board.zig");
const Piece = board.Piece;
const Color = board.Color;
const PieceType = board.PieceType;
const bitboard = @import("bitboard.zig");

/// Bit mask for masking off the third rank
const THIRD_RANK: u64 = 0x0000FF0000000000;
/// Bit mask for masking off the fifth rank
const FIFTH_RANK: u64 = 0x00000000FF000000;

/// Bitmask for detecting pieces that block white from queenside castling
const WHITE_QUEENSIDE_BLOCKERS = 0xe00000000000000;
/// Bitmask for detecting pieces that block white from kingside castling
const WHITE_KINGSIDE_BLOCKERS = 0x6000000000000000;
/// Bitmask for detecting pieces that block black from queenside castling
const BLACK_QUEENSIDE_BLOCKERS = 0xe;
/// Bitmask for detecting pieces that block black from kingside castling
const BLACK_KINGSIDE_BLOCKERS = 0x60;

/// Bitflag representation of move properties, mostly same as
/// https://github.com/nkarve/surge/blob/c4ea4e2655cc938632011672ddc880fefe7d02a6/src/types.h#L146-L157
pub const MoveType = enum(u4) {
    /// The move does not capture anything and isn't special either
    QUIET,
    /// A pawn was moved two squares
    /// This is relevant because of en passant
    DOUBLE_PUSH,
    /// Castle Kingside
    CASTLE_SHORT,
    /// Castle Queenside
    CASTLE_LONG,
    /// The move captures a piece
    CAPTURE,
    /// Capture a pawn en-passant
    EN_PASSANT,
    /// Promote to a knight
    PROMOTE_KNIGHT,
    /// Promote to a rook
    PROMOTE_ROOK,
    /// Promote to a bishop
    PROMOTE_BISHOP,
    /// Promote to a queen
    PROMOTE_QUEEN,
    /// Capture a piece and promote to a knight
    CAPTURE_PROMOTE_KNIGHT,
    /// Capture a piece and promote to a rook
    CAPTURE_PROMOTE_ROOK,
    /// Capture a piece and promote to a bishop
    CAPTURE_PROMOTE_BISHOP,
    /// Capture a piece and promote to a queen
    CAPTURE_PROMOTE_QUEEN,
};

pub const Move = struct {
    /// Source square
    from: u6,
    /// Target square
    to: u6,
    /// Move properties
    move_type: MoveType,

    pub fn quiet(from: u6, to: u6) Move {
        return Move{
            .from = from,
            .to = to,
            .move_type = MoveType.QUIET,
        };
    }

    pub inline fn is_capture(self: *Move) bool {
        return (self.flags & MoveType.CAPTURE) != 0;
    }
};

pub const MoveCallback = fn (move: Move) void;

const Pinmask = struct {
    straight: u64,
    diagonal: u64,
    both: u64,
};

/// A pinmask contains the squares from the pinning piece (opponent) to our king.
/// By &-ing possible moves for the pinned pieces with this mask, legal moves are easily generated.
/// The pinmask includes the pinning piece (capturing resolves the pin) and is split into diagonal/straight
/// pins to avoid edge cases.
pub fn generate_pinmask(game: board.Board) Pinmask {
    const us = game.active_color;
    const them = us.other();
    const king_square = bitboard.get_lsb_square(game.get_bitboard(Piece.new(us, PieceType.king)));
    const diag_attackers = game.get_bitboard(Piece.new(us, PieceType.bishop)) | game.get_bitboard(Piece.new(us, PieceType.queen));
    const straight_attackers = game.get_bitboard(Piece.new(us, PieceType.rook)) | game.get_bitboard(Piece.new(them, PieceType.queen));

    // diagonal pins
    const diag_blockers = bitboard.bishop_attacks(king_square, game.get_occupancies(Color.both)) & game.get_occupancies(us);
    const diag_xray_attacks = bitboard.bishop_attacks(king_square, game.get_occupancies(Color.both) ^ diag_blockers);
    var diag_pinners: u64 = diag_xray_attacks & diag_attackers;
    var diag_pinmask: u64 = diag_pinners; // capturing the pinning piece is valid
    while (diag_pinners != 0) : (bitops.pop_ls1b(&diag_pinners)) {
        const pinner_square = bitboard.get_lsb_square(diag_pinners);
        diag_pinmask |= diag_xray_attacks & bitboard.bishop_attacks(pinner_square, game.get_bitboard(Piece.new(us, PieceType.king)));
    }

    // straight pins
    const straight_blockers = bitboard.rook_attacks(king_square, game.get_occupancies(Color.both)) & game.get_occupancies(us);
    const straight_xray_attacks = bitboard.rook_attacks(king_square, game.get_occupancies(Color.both) ^ straight_blockers);
    var straight_pinners: u64 = straight_xray_attacks & straight_attackers;
    var straight_pinmask: u64 = straight_pinners; // capturing the pinning piece is valid
    while (straight_pinners != 0) : (bitops.pop_ls1b(&straight_pinners)) {
        const pinner_square = bitboard.get_lsb_square(straight_pinners);
        straight_pinmask |= straight_xray_attacks & bitboard.rook_attacks(pinner_square, game.get_bitboard(Piece.new(us, PieceType.king)));
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
    const us = game.active_color;
    const them = us.other();
    const opponent_diag_sliders = game.get_bitboard(Piece.new(them, PieceType.bishop)) | game.get_bitboard(Piece.new(them, PieceType.queen));
    const opponent_straight_sliders = game.get_bitboard(Piece.new(them, PieceType.rook)) | game.get_bitboard(Piece.new(them, PieceType.queen));
    const king_square = bitboard.get_lsb_square(game.get_bitboard(Piece.new(us, PieceType.king)));

    var checkmask: u64 = 0;
    var in_check: bool = false;

    // there can at most be one diag slider attacking the king (even with promotions, i think)
    const attacking_diag_slider = bitboard.bishop_attacks(king_square, game.get_occupancies(Color.both)) & opponent_diag_sliders;
    if (attacking_diag_slider != 0) {
        const attacker_square = bitboard.get_lsb_square(attacking_diag_slider);
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[attacker_square][king_square];
        in_check = true;
    }

    const attacking_straight_slider = bitboard.rook_attacks(king_square, game.get_occupancies(Color.both)) & opponent_straight_sliders;
    if (attacking_straight_slider != 0) {
        const attacker_square = bitboard.get_lsb_square(attacking_straight_slider);
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[attacker_square][king_square];
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_knight = bitboard.knight_attack(king_square) & game.get_bitboard(Piece.new(them, PieceType.knight));
    if (attacking_knight != 0) {
        const knight_square = bitboard.get_lsb_square(attacking_knight);
        checkmask |= bitboard.PATH_BETWEEN_SQUARES[knight_square][king_square];
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_pawns = switch (us) {
        Color.white => bitboard.white_pawn_attacks(game.get_bitboard(Piece.new(us, PieceType.king))) & game.get_bitboard(Piece.new(them, PieceType.pawn)),
        Color.black => bitboard.black_pawn_attacks(game.get_bitboard(Piece.new(us, PieceType.king))) & game.get_bitboard(Piece.new(them, PieceType.pawn)),
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
    const us = game.active_color;
    const diag_sliders = game.get_bitboard(Piece.new(us, PieceType.bishop)) | game.get_bitboard(Piece.new(us, PieceType.queen));
    const straight_sliders = game.get_bitboard(Piece.new(us, PieceType.rook)) | game.get_bitboard(Piece.new(us, PieceType.queen));
    const enemy_or_empty = ~game.get_occupancies(us);
    const checkmask = generate_checkmask(game);
    const pinmask = generate_pinmask(game);

    // legal king moves

    // when we're in double check, only the king is allowed to move
    if (checkmask == 0) return;

    // legal knight moves
    // pinned knights can never move
    var unpinned_knights = game.get_bitboard(Piece.new(us, PieceType.knight)) & ~pinmask.both;
    while (unpinned_knights != 0) : (bitops.pop_ls1b(&unpinned_knights)) {
        const square = @truncate(u6, @ctz(u64, unpinned_knights));
        var knight_moves = bitboard.knight_attack(square) & enemy_or_empty & checkmask;
        while (knight_moves != 0) : (bitops.pop_ls1b(&knight_moves)) {
            const to = @truncate(u6, @ctz(u64, knight_moves));
            callback(Move{
                .from = square,
                .to = to,
                .move_type = MoveType.QUIET,
            });
        }
    }

    // legal diagonal slider moves
    // straight pinned diagonal sliders can never move
    var unpinned_bishops = diag_sliders & ~pinmask.both;
    while (unpinned_bishops != 0) : (bitops.pop_ls1b(&unpinned_bishops)) {
        const square = bitboard.get_lsb_square(unpinned_bishops);
        var moves = bitboard.bishop_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask;
        while (moves != 0) : (bitops.pop_ls1b(&moves)) {
            const to = bitboard.get_lsb_square(moves);
            callback(Move{
                .from = square,
                .to = to,
                .move_type = MoveType.QUIET,
            });
        }
    }

    var pinned_bishops = diag_sliders & pinmask.diagonal;
    while (pinned_bishops != 0) : (bitops.pop_ls1b(&pinned_bishops)) {
        const square = bitboard.get_lsb_square(pinned_bishops);
        var moves = bitboard.bishop_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask & pinmask.diagonal;
        while (moves != 0) : (bitops.pop_ls1b(&moves)) {
            const to = bitboard.get_lsb_square(moves);
            callback(Move{
                .from = square,
                .to = to,
                .move_type = MoveType.QUIET,
            });
        }
    }

    // legal straight slider moves
    // diagonally pinned straight sliders can never move
    var unpinned_rooks = straight_sliders & ~pinmask.both;
    while (unpinned_rooks != 0) : (bitops.pop_ls1b(&unpinned_rooks)) {
        const square = bitboard.get_lsb_square(unpinned_rooks);
        var moves = bitboard.rook_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask;
        while (moves != 0) : (bitops.pop_ls1b(&moves)) {
            const to = bitboard.get_lsb_square(moves);
            callback(Move{
                .from = square,
                .to = to,
                .move_type = MoveType.QUIET,
            });
        }
    }

    var pinned_rooks = straight_sliders & pinmask.diagonal;
    while (pinned_rooks != 0) : (bitops.pop_ls1b(&pinned_rooks)) {
        const square = bitboard.get_lsb_square(pinned_rooks);
        var moves = bitboard.rook_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask & pinmask.diagonal;
        while (moves != 0) : (bitops.pop_ls1b(&pinned_rooks)) {
            const to = bitboard.get_lsb_square(moves);
            callback(Move{
                .from = square,
                .to = to,
                .move_type = MoveType.QUIET,
            });
        }
    }

    // legal pawn moves (moved to external function to avoid repeated if(white)'s
    switch (us) {
        Color.white => {
            white_pawn_moves(game, callback, checkmask, pinmask);
        },
        Color.black => {},
        else => unreachable,
    }
}

fn white_pawn_moves(game: board.Board, emit: MoveCallback, checkmask: u64, pinmask: Pinmask) void {
    // Terminology:
    // moving => move pawn one square
    // pushing => move pawn two squares
    // moving/pushing uses the straight pinmask, capturing the diagonal one (like a queen)
    const empty = ~game.get_occupancies(Color.both);
    const white_pawns = game.get_bitboard(Piece.new(Color.white, PieceType.pawn));

    // pawn moves
    var legal_pawn_moves: u64 = 0;
    const straight_pinned_pawns = white_pawns & pinmask.straight;
    const pinned_pawn_moves = straight_pinned_pawns >> 8 & pinmask.straight & empty; // needed later for pawn pushes
    legal_pawn_moves |= pinned_pawn_moves;

    const unpinned_pawns = white_pawns & ~pinmask.both;
    const unpinned_pawn_moves = unpinned_pawns >> 8 & empty;
    legal_pawn_moves |= unpinned_pawn_moves;

    legal_pawn_moves &= checkmask; // prune moves that leave the king in check
    while (legal_pawn_moves != 0) : (bitops.pop_ls1b(&legal_pawn_moves)) {
        const to = bitboard.get_lsb_square(legal_pawn_moves);
        emit(Move{
            .from = to + 8,
            .to = to,
            .move_type = MoveType.QUIET,
        });
    }

    // pawn pushes
    // no pinmask required here - if we were able to move then we are also able to push ^^
    var pawn_pushes: u64 = ((pinned_pawn_moves | unpinned_pawn_moves) & THIRD_RANK) >> 8 & empty & checkmask;
    while (pawn_pushes != 0) : (bitops.pop_ls1b(&pawn_pushes)) {
        const to = bitboard.get_lsb_square(pawn_pushes);
        emit(Move{
            .from = to + 16,
            .to = to,
            .move_type = MoveType.QUIET,
        });
    }

    // pawn captures
    var left_captures: u64 = 0;
    var right_captures: u64 = 0;

    const diag_pinned_pawns = white_pawns & pinmask.diagonal;
    left_captures |= bitboard.white_pawn_attacks_left(diag_pinned_pawns) & pinmask.diagonal;
    left_captures |= bitboard.white_pawn_attacks_left(unpinned_pawns);

    right_captures |= bitboard.white_pawn_attacks_right(diag_pinned_pawns) & pinmask.diagonal;
    right_captures |= bitboard.white_pawn_attacks_right(unpinned_pawns);

    left_captures &= game.get_occupancies(Color.black);
    right_captures &= game.get_occupancies(Color.black);
    left_captures &= checkmask;
    right_captures &= checkmask;

    while (left_captures != 0) : (bitops.pop_ls1b(&left_captures)) {
        const to = bitboard.get_lsb_square(left_captures);
        emit(Move{
            .from = to + 9,
            .to = to,
            .move_type = MoveType.CAPTURE,
        });
    }

    while (right_captures != 0) : (bitops.pop_ls1b(&right_captures)) {
        const to = bitboard.get_lsb_square(right_captures);
        emit(Move{
            .from = to + 7,
            .to = to,
            .move_type = MoveType.CAPTURE,
        });
    }
}

test "checkmask generation" {
    const expectEqual = std.testing.expectEqual;

    // Simple check
    const simple = try board.Board.from_fen("8/8/5q2/8/8/2K5/8/8 w - - 0 0");
    try expectEqual(@as(u7, 3), @popCount(u64, generate_checkmask(simple)));

    // Double check - no moves (except king moves) allowed
    const double = try board.Board.from_fen("8/8/5q2/8/1p6/2K5/8/8 w - - 0 0");
    try expectEqual(@as(u64, 0), generate_checkmask(double));

    // No check
    const no_check = try board.Board.from_fen("8/8/8/3K4/8/8/8/8 w - - 0 0");
    try expectEqual(~@as(u64, 0), generate_checkmask(no_check));
}
