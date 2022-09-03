// //! Generates legal chess moves in a given position
const std = @import("std");

const pop_ls1b = @import("bitops.zig").pop_ls1b;

const ArrayList = std.ArrayList;

const board = @import("board.zig");
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;
const Move = board.Move;
const MoveType = board.MoveType;
const PieceType = board.PieceType;

// const Square = board.Square;
// const PieceType = board.PieceType;

const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;
const bishop_attacks = bitboard.bishop_attacks;
const rook_attacks = bitboard.rook_attacks;
const get_lsb_square = bitboard.get_lsb_square;

// /// Bit mask for masking off the third rank
// const THIRD_RANK: u64 = 0x0000FF0000000000;
// /// Bit mask for masking off the fifth rank
// const FIFTH_RANK: u64 = 0x00000000FF000000;
//
// /// Bitmask for detecting pieces that block white from queenside castling
// const WHITE_QUEENSIDE = 0xe00000000000000;
// /// Bitmask for detecting pieces that block white from kingside castling
// const WHITE_KINGSIDE = 0x6000000000000000;
// /// Bitmask for detecting pieces that block black from queenside castling
// const BLACK_QUEENSIDE = 0xe;
// /// Bitmask for detecting pieces that block black from kingside castling
// const BLACK_KINGSIDE = 0x60;

const Pinmask = struct {
    straight: Bitboard,
    diagonal: Bitboard,
    both: Bitboard,
};

/// A pinmask contains the squares from the pinning piece (opponent) to our king.
/// By &-ing possible moves for the pinned pieces with this mask, legal moves are easily generated.
/// The pinmask includes the pinning piece (capturing resolves the pin) and is split into diagonal/straight
/// pins to avoid edge cases.
pub fn generate_pinmask(comptime us: Color, position: Position) Pinmask {
    const them = comptime us.other();
    const king_square = bitboard.get_lsb_square(position.king(us));
    const diag_attackers = position.bishops(them) | position.queens(them);
    const straight_attackers = position.rooks(them) | position.queens(them);

    // diagonal pins
    const diag_attacks_raw = bishop_attacks(king_square, position.occupied);
    const diag_blockers = diag_attacks_raw & position.occupied_by(us);
    const diag_attacks_all = bishop_attacks(king_square, position.occupied ^ diag_blockers);
    const diag_xray_attacks = diag_attacks_all ^ diag_attacks_raw;

    var diag_pinners = diag_xray_attacks & diag_attackers;
    var diag_pinmask = diag_pinners; // capturing the pinning piece is valid
    while (diag_pinners != 0) : (pop_ls1b(&diag_pinners)) {
        const pinner_square = get_lsb_square(diag_pinners);
        diag_pinmask |= diag_attacks_all & bishop_attacks(pinner_square, position.king(us));
    }

    // straight pins
    const straight_attacks_raw = rook_attacks(king_square, position.occupied);
    const straight_blockers = straight_attacks_raw & position.occupied_by(us);
    const straight_attacks_all = rook_attacks(king_square, position.occupied ^ straight_blockers);
    const straight_xray_attacks = straight_attacks_all ^ straight_attacks_raw;
    var straight_pinners = straight_xray_attacks & straight_attackers;

    var straight_pinmask = straight_pinners; // capturing the pinning piece is valid
    while (straight_pinners != 0) : (pop_ls1b(&straight_pinners)) {
        const pinner_square = get_lsb_square(straight_pinners);
        straight_pinmask |= straight_attacks_all & rook_attacks(pinner_square, position.king(us));
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
pub fn generate_checkmask(comptime us: Color, position: Position) Bitboard {
    const them = comptime us.other();
    const opponent_diag_sliders = position.bishops(them) | position.queens(them);
    const opponent_straight_sliders = position.rooks(them) | position.queens(them);
    const king_square = get_lsb_square(position.king(us));

    var checkmask: Bitboard = 0;
    var in_check: bool = false;

    // there can at most be one diag slider attacking the king (even with promotions, i think)
    const attacking_diag_slider = bishop_attacks(king_square, position.occupied) & opponent_diag_sliders;
    if (attacking_diag_slider != 0) {
        const attacker_square = get_lsb_square(attacking_diag_slider);
        checkmask |= bitboard.path_between_squares(attacker_square, king_square);
        in_check = true;
    }

    const attacking_straight_slider = rook_attacks(king_square, position.occupied) & opponent_straight_sliders;
    if (attacking_straight_slider != 0) {
        const attacker_square = get_lsb_square(attacking_straight_slider);
        checkmask |= bitboard.path_between_squares(attacker_square, king_square);
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_knight = bitboard.knight_attack(king_square) & position.knights(them);
    if (attacking_knight != 0) {
        const knight_square = get_lsb_square(attacking_knight);
        checkmask |= knight_square.as_board();
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_pawns = bitboard.pawn_attacks(us, position.king(us)) & position.pawns(them);

    if (attacking_pawns != 0) {
        const pawn_square = get_lsb_square(attacking_pawns);
        checkmask |= pawn_square.as_board();
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    if (in_check) return checkmask;
    return ~@as(u64, 0);
}

fn add_all(from: Bitboard, moves: Bitboard, list: *ArrayList(Move), move_type: MoveType) !void {
    var remaining_moves = moves;
    while (remaining_moves != 0) : (pop_ls1b(&remaining_moves)) {
        const to = get_lsb_square(remaining_moves);
        try list.append(Move{
            .from = from,
            .to = to.as_board(),
            .move_type = move_type,
        });
    }
}

// Caller owns returned memory
pub fn generate_moves(comptime state: BoardRights, pos: Position, gpa: anytype) !ArrayList(Move) {
    const us = comptime state.active_color;
    const them = comptime state.active_color.other();
    const king_unsafe_squares = pos.king_unsafe_squares(us);
    // const diag_sliders = pos.bishops(us) | pos.queens(us);
    // const straight_sliders = pos.rooks(us) | pos.queens(us);
    const enemy_or_empty = ~pos.occupied_by(us);
    const enemy = pos.occupied_by(them);
    const empty = ~pos.occupied;
    const checkmask = generate_checkmask(us, pos);
    const pinmask = generate_pinmask(us, pos);
    var move_list = ArrayList(Move).init(gpa);

    // legal king moves
    const king_attacks = bitboard.king_attacks(pos.king(us)) & ~king_unsafe_squares;
    try add_all(pos.king(us), king_attacks & empty, &move_list, MoveType{ .quiet = PieceType.king });
    try add_all(pos.king(us), king_attacks & enemy, &move_list, MoveType{ .capture = PieceType.king });

    // when we're in double check, only the king is allowed to move
    if (checkmask == 0) return move_list;

    // legal knight moves
    // pinned knights can never move
    var unpinned_knights = pos.knights(us) & ~pinmask.both;
    while (unpinned_knights != 0) : (pop_ls1b(&unpinned_knights)) {
        const square = get_lsb_square(unpinned_knights);
        const moves = bitboard.knight_attack(square) & enemy_or_empty & checkmask;
        try add_all(square.as_board(), moves & empty, &move_list, MoveType{ .quiet = PieceType.knight });
        try add_all(square.as_board(), moves & enemy, &move_list, MoveType{ .capture = PieceType.knight });
    }
    return move_list;

    // // legal diagonal slider moves
    // // straight pinned diagonal sliders can never move
    // var unpinned_bishops = diag_sliders & ~pinmask.both;
    // while (unpinned_bishops != 0) : (bitops.pop_ls1b(&unpinned_bishops)) {
    //     const square = bitboard.get_lsb_square(unpinned_bishops);
    //     const moves = bitboard.bishop_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask;
    //     emit_all(square, moves & empty, emit, MoveType.QUIET);
    //     emit_all(square, moves & enemy, emit, MoveType.CAPTURE);
    // }

    // var pinned_bishops = diag_sliders & pinmask.diagonal;
    // while (pinned_bishops != 0) : (bitops.pop_ls1b(&pinned_bishops)) {
    //     const square = bitboard.get_lsb_square(pinned_bishops);
    //     const moves = bitboard.bishop_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask & pinmask.diagonal;
    //     emit_all(square, moves & empty, emit, MoveType.QUIET);
    //     emit_all(square, moves & enemy, emit, MoveType.CAPTURE);
    // }

    // // legal straight slider moves
    // // diagonally pinned straight sliders can never move
    // var unpinned_rooks = straight_sliders & ~pinmask.both;
    // while (unpinned_rooks != 0) : (bitops.pop_ls1b(&unpinned_rooks)) {
    //     const square = bitboard.get_lsb_square(unpinned_rooks);
    //     var moves = bitboard.rook_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask;
    //     emit_all(square, moves & empty, emit, MoveType.QUIET);
    //     emit_all(square, moves & enemy, emit, MoveType.CAPTURE);
    // }

    // var pinned_rooks = straight_sliders & pinmask.diagonal;
    // while (pinned_rooks != 0) : (bitops.pop_ls1b(&pinned_rooks)) {
    //     const square = bitboard.get_lsb_square(pinned_rooks);
    //     var moves = bitboard.rook_attacks(square, game.get_occupancies(Color.both)) & enemy_or_empty & checkmask & pinmask.diagonal;
    //     emit_all(square, moves & empty, emit, MoveType.QUIET);
    //     emit_all(square, moves & enemy, emit, MoveType.CAPTURE);
    // }

    // // legal pawn moves (moved to external function to avoid repeated if(white)'s
    // // (performance gud, we do constexpr by hand ^^)
    // switch (us) {
    //     Color.white => {
    //         pawn_moves(Color.white, game, emit, checkmask, pinmask);
    //         castle(Color.white, game, emit, king_unsafe_squares);
    //     },
    //     Color.black => {
    //         castle(Color.black, game, emit, king_unsafe_squares);
    //     },
    //     else => unreachable,
    // }
}
//
// fn castle(comptime color: Color, game: board.Board, emit: MoveCallback, king_unsafe_squares: u64) void {
//     // cannot castle either way when in check
//     if (color == Color.white) {
//         if (game.get_bitboard(Piece.white_king) & king_unsafe_squares != 0) return;
//     } else {
//         if (game.get_bitboard(Piece.black_king) & king_unsafe_squares != 0) return;
//     }
//
//     // The squares we traverse must not be in check or occupied
//     const travel_blockers = (game.get_occupancies(Color.both) | king_unsafe_squares);
//     const queenside_blockers = travel_blockers & WHITE_QUEENSIDE;
//     const kingside_blockers = travel_blockers & WHITE_KINGSIDE;
//     if (game.castling_rights.queenside(color) and queenside_blockers == 0) {
//         if (color == Color.white) {
//             emit(Move{
//                 .from = Square.E1,
//                 .to = Square.C1,
//                 .move_type = MoveType.CASTLE_LONG,
//             });
//         } else {
//             emit(Move{
//                 .from = Square.E8,
//                 .to = Square.C8,
//                 .move_type = MoveType.CASTLE_LONG,
//             });
//         }
//     }
//
//     if (game.castling_rights.kingside(color) and kingside_blockers == 0) {
//         if (color == Color.white) {
//             emit(Move{
//                 .from = Square.E1,
//                 .to = Square.G1,
//                 .move_type = MoveType.CASTLE_SHORT,
//             });
//         } else {
//             emit(Move{
//                 .from = Square.E8,
//                 .to = Square.G8,
//                 .move_type = MoveType.CASTLE_SHORT,
//             });
//         }
//     }
// }
//
// fn pawn_moves(comptime color: Color, game: board.Board, emit: MoveCallback, checkmask: u64, pinmask: Pinmask) void {
//     // Terminology:
//     // moving => move pawn one square
//     // pushing => move pawn two squares
//     // moving/pushing uses the straight pinmask, capturing the diagonal one (like a queen)
//     const empty = ~game.get_occupancies(Color.both);
//     const white_pawns = game.get_bitboard(Piece.white_pawn);
//
//     // pawn moves
//     var legal_pawn_moves: Bitboard = 0;
//     const straight_pinned_pawns = white_pawns & pinmask.straight;
//     const pinned_pawn_moves = straight_pinned_pawns >> 8 & pinmask.straight & empty; // needed later for pawn pushes
//     legal_pawn_moves |= pinned_pawn_moves;
//
//     const unpinned_pawns = white_pawns & ~pinmask.both;
//     const unpinned_pawn_moves = unpinned_pawns >> 8 & empty;
//     legal_pawn_moves |= unpinned_pawn_moves;
//
//     legal_pawn_moves &= checkmask; // prune moves that leave the king in check
//     while (legal_pawn_moves != 0) : (bitops.pop_ls1b(&legal_pawn_moves)) {
//         const to = bitboard.get_lsb_square(legal_pawn_moves);
//         emit(Move{
//             .from = to.down_one(),
//             .to = to,
//             .move_type = MoveType.QUIET,
//         });
//     }
//
//     // pawn pushes
//     // no pinmask required here - if we were able to move then we are also able to push ^^
//     var pawn_pushes: u64 = ((pinned_pawn_moves | unpinned_pawn_moves) & THIRD_RANK) >> 8 & empty & checkmask;
//     while (pawn_pushes != 0) : (bitops.pop_ls1b(&pawn_pushes)) {
//         const to = bitboard.get_lsb_square(pawn_pushes);
//         emit(Move{
//             .from = to.down_two(),
//             .to = to,
//             .move_type = MoveType.QUIET,
//         });
//     }
//
//     // pawn captures
//     var left_captures: Bitboard = 0;
//     var right_captures: Bitboard = 0;
//
//     const diag_pinned_pawns = white_pawns & pinmask.diagonal;
//     left_captures |= bitboard.pawn_attacks_left(color, diag_pinned_pawns) & pinmask.diagonal;
//     left_captures |= bitboard.pawn_attacks_left(color, unpinned_pawns);
//
//     right_captures |= bitboard.pawn_attacks_right(color, diag_pinned_pawns) & pinmask.diagonal;
//     right_captures |= bitboard.pawn_attacks_right(color, unpinned_pawns);
//
//     left_captures &= game.get_occupancies(Color.black);
//     right_captures &= game.get_occupancies(Color.black);
//     left_captures &= checkmask;
//     right_captures &= checkmask;
//
//     while (left_captures != 0) : (bitops.pop_ls1b(&left_captures)) {
//         const to = bitboard.get_lsb_square(left_captures);
//         emit(Move{
//             .from = to.down_right(),
//             .to = to,
//             .move_type = MoveType.CAPTURE,
//         });
//     }
//
//     while (right_captures != 0) : (bitops.pop_ls1b(&right_captures)) {
//         const to = bitboard.get_lsb_square(right_captures);
//         emit(Move{
//             .from = to.down_left(),
//             .to = to,
//             .move_type = MoveType.CAPTURE,
//         });
//     }
// }
//
// /// Utility tool for emitting multiple moves with a common move type
// inline fn emit_all(from: Square, targets: u64, emit: MoveCallback, move_type: MoveType) void {
//     var remaining_targets = targets;
//     while (remaining_targets != 0) : (bitops.pop_ls1b(&remaining_targets)) {
//         const to = bitboard.get_lsb_square(remaining_targets);
//         emit(Move{
//             .from = from,
//             .to = to,
//             .move_type = move_type,
//         });
//     }
// }
//
//
// // test "Move to string" {
// //     const expectEqual = std.testing.expectEqual;
// //
// //     const regular = Move{
// //         .from = Square.C2,
// //         .to = Square.C5,
// //         .move_type = MoveType.CASTLE_SHORT,
// //     };
// //     try expectEqual(regular.to_str(), "c2c5");
// //
// //     const castle = Move{
// //         .from = Square.E1,
// //         .to = Square.G1,
// //         .move_type = MoveType.CASTLE_SHORT,
// //     };
// //     try expectEqual(castle.to_str(), "e1g1");
// //
// //     const capture_promote = Move{
// //         .from = Square.E7,
// //         .to = Square.D8,
// //         .move_type = MoveType.CAPTURE_PROMOTE_KNIGHT,
// //     };
// //     try expectEqual(capture_promote.to_str(), "e7d8n");
// //
// //     const promote = Move{
// //         .from = Square.E7,
// //         .to = Square.E8,
// //         .move_type = MoveType.PROMOTE_KNIGHT,
// //     };
// //     try expectEqual(promote.to_str(), "e7e8n");
// // }

test "generate pinmask" {
    const expectEqual = std.testing.expectEqual;

    // contains straight pins, diagonal pins and various setups
    // that look like pins, but actually aren't
    const position = Position.from_fen("1b6/4P1P1/4r3/rP2K3/8/2P5/8/b7") catch unreachable;
    const pins = generate_pinmask(Color.white, position);

    try expectEqual(@as(Bitboard, 0x10204080f000000), pins.both);
    try expectEqual(@as(Bitboard, 0xf000000), pins.straight);
    try expectEqual(@as(Bitboard, 0x102040800000000), pins.diagonal);
}

test "checkmask generation" {
    const expectEqual = std.testing.expectEqual;

    // Simple check, only blocking/capturing the checking piece is allowed
    const simple = try Position.from_fen("8/1q5b/8/5P2/4K3/8/8/8");
    try expectEqual(@as(Bitboard, 0x8040200), generate_checkmask(Color.white, simple));

    // Double check - no moves (except king moves) allowed
    const double = try Position.from_fen("8/8/5q2/8/1p6/2K5/8/8");
    try expectEqual(@as(Bitboard, 0), generate_checkmask(Color.white, double));

    // No check, all moves allowed
    const no_check = try Position.from_fen("8/8/8/3K4/8/8/8/8");
    try expectEqual(~@as(Bitboard, 0), generate_checkmask(Color.white, no_check));
}
