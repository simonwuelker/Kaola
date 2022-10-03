// //! Generates legal chess moves in a given position
const std = @import("std");

const pop_ls1b = @import("bitops.zig").pop_ls1b;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const board = @import("board.zig");
const GameState = board.GameState;
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;
const Move = board.Move;
const MoveType = board.MoveType;
const PieceType = board.PieceType;
const Square = board.Square;

const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;
const bishop_attacks = bitboard.bishop_attacks;
const pawn_attacks_left = bitboard.pawn_attacks_left;
const pawn_attacks_right = bitboard.pawn_attacks_right;
const pawn_attacks = bitboard.pawn_attacks;
const rook_attacks = bitboard.rook_attacks;
const get_lsb_square = bitboard.get_lsb_square;

/// Bitmask for detecting pieces that block white from queenside castling
const WHITE_QUEENSIDE = 0xe00000000000000;
/// Bitmask for detecting pieces that block white from kingside castling
const WHITE_KINGSIDE = 0x6000000000000000;
/// Bitmask for detecting pieces that block black from queenside castling
const BLACK_QUEENSIDE = 0xe;
/// Bitmask for detecting pieces that block black from kingside castling
const BLACK_KINGSIDE = 0x60;

fn kingside_blockers(comptime color: Color) Bitboard {
    switch (color) {
        Color.white => return WHITE_KINGSIDE,
        Color.black => return BLACK_KINGSIDE,
    }
}

fn queenside_blockers(comptime color: Color) Bitboard {
    switch (color) {
        Color.white => return WHITE_QUEENSIDE,
        Color.black => return BLACK_QUEENSIDE,
    }
}

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

    // Note that pawns/knights cannot cause double check

    const attacking_pawns = bitboard.pawn_attacks(us, position.king(us)) & position.pawns(them);
    if (attacking_pawns != 0) {
        const pawn_square = get_lsb_square(attacking_pawns);
        checkmask |= pawn_square.as_board();
        in_check = true;
    }

    const attacking_knight = bitboard.knight_attack(king_square) & position.knights(them);
    if (attacking_knight != 0) {
        const knight_square = get_lsb_square(attacking_knight);
        checkmask |= knight_square.as_board();
        in_check = true;
    }

    // there can at most be one diag slider attacking the king (even with promotions, i think)
    const attacking_diag_slider = bishop_attacks(king_square, position.occupied) & opponent_diag_sliders;
    if (attacking_diag_slider != 0) {
        const attacker_square = get_lsb_square(attacking_diag_slider);
        checkmask |= bitboard.path_between_squares(attacker_square, king_square);
        if (in_check) return 0; // double check, no way to block/capture
        in_check = true;
    }

    const attacking_straight_slider = rook_attacks(king_square, position.occupied) & opponent_straight_sliders;
    if (attacking_straight_slider != 0) {
        const attacker_square = get_lsb_square(attacking_straight_slider);
        checkmask |= bitboard.path_between_squares(attacker_square, king_square);
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
pub fn generate_moves(comptime us: Color, state: GameState, move_list: *ArrayList(Move)) Allocator.Error!void {
    const them = comptime us.other();
    const pos = state.position;
    const king_unsafe_squares = pos.king_unsafe_squares(us);
    const diag_sliders = pos.bishops(us) | pos.queens(us);
    const straight_sliders = pos.rooks(us) | pos.queens(us);
    const enemy_or_empty = ~pos.occupied_by(us);
    const enemy = pos.occupied_by(them);
    const empty = ~pos.occupied;
    const checkmask = generate_checkmask(us, pos);
    const pinmask = generate_pinmask(us, pos);

    // legal king moves
    const king_attacks = bitboard.king_attacks(pos.king(us)) & ~king_unsafe_squares;
    try add_all(pos.king(us), king_attacks & empty, move_list, MoveType{ .quiet = PieceType.king });
    try add_all(pos.king(us), king_attacks & enemy, move_list, MoveType{ .capture = PieceType.king });

    // when we're in double check, only the king is allowed to move
    if (checkmask == 0) return;

    // legal knight moves
    // pinned knights can never move
    var unpinned_knights = pos.knights(us) & ~pinmask.both;
    while (unpinned_knights != 0) : (pop_ls1b(&unpinned_knights)) {
        const square = get_lsb_square(unpinned_knights);
        const moves = bitboard.knight_attack(square) & enemy_or_empty & checkmask;
        try add_all(square.as_board(), moves & empty, move_list, MoveType{ .quiet = PieceType.knight });
        try add_all(square.as_board(), moves & enemy, move_list, MoveType{ .capture = PieceType.knight });
    }

    // legal diagonal slider moves
    // straight pinned diagonal sliders can never move
    var unpinned_bishops = diag_sliders & ~pinmask.both;
    var pinned_bishops = diag_sliders & pinmask.diagonal;
    while (unpinned_bishops != 0) : (pop_ls1b(&unpinned_bishops)) {
        const square = get_lsb_square(unpinned_bishops);
        const moves = bishop_attacks(square, pos.occupied) & enemy_or_empty & checkmask;
        const from = square.as_board();

        if (from & pos.bishops(us) != 0) {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.bishop });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.bishop });
        } else {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.queen });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.queen });
        }
    }

    while (pinned_bishops != 0) : (pop_ls1b(&pinned_bishops)) {
        const square = get_lsb_square(pinned_bishops);
        const moves = bishop_attacks(square, pos.occupied) & enemy_or_empty & checkmask & pinmask.diagonal;
        const from = square.as_board();

        if (from & pos.bishops(us) != 0) {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.bishop });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.bishop });
        } else {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.queen });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.queen });
        }
    }

    // legal straight slider moves
    // diagonally pinned straight sliders can never move
    var unpinned_rooks = straight_sliders & ~pinmask.both;
    while (unpinned_rooks != 0) : (pop_ls1b(&unpinned_rooks)) {
        const square = get_lsb_square(unpinned_rooks);
        const moves = rook_attacks(square, pos.occupied) & enemy_or_empty & checkmask;
        const from = square.as_board();

        if (from & pos.rooks(us) != 0) {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.rook });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.rook });
        } else {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.queen });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.queen });
        }
    }

    var pinned_rooks = straight_sliders & pinmask.straight;
    while (pinned_rooks != 0) : (pop_ls1b(&pinned_rooks)) {
        const square = get_lsb_square(pinned_rooks);
        const moves = rook_attacks(square, pos.occupied) & enemy_or_empty & checkmask & pinmask.straight;
        const from = square.as_board();

        if (from & pos.rooks(us) != 0) {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.rook });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.rook });
        } else {
            try add_all(from, moves & empty, move_list, MoveType{ .quiet = PieceType.queen });
            try add_all(from, moves & enemy, move_list, MoveType{ .capture = PieceType.queen });
        }
    }

    // try pawn_moves(us, pos, move_list, checkmask, pinmask);
    try castle(us, state, move_list, king_unsafe_squares);
    try pawn_moves(us, state, move_list, checkmask, pinmask);
    return;
}

fn castle(comptime us: Color, state: GameState, move_list: *ArrayList(Move), king_unsafe_squares: Bitboard) !void {
    // cannot castle either way when in check
    if (state.position.king(us) & king_unsafe_squares != 0) return;

    // The squares we traverse must not be in check or occupied
    const blockers = state.position.occupied | king_unsafe_squares;
    if (state.can_castle_queenside(us) and blockers & queenside_blockers(us) == 0) {
        switch (us) {
            Color.white => {
                try move_list.append(Move{
                    .from = Square.E1.as_board(),
                    .to = Square.C1.as_board(),
                    .move_type = MoveType{ .castle = board.WHITE_QUEENSIDE },
                });
            },
            Color.black => {
                try move_list.append(Move{
                    .from = Square.E8.as_board(),
                    .to = Square.C8.as_board(),
                    .move_type = MoveType{ .castle = board.BLACK_QUEENSIDE },
                });
            },
        }
    }

    if (state.can_castle_kingside(us) and blockers & kingside_blockers(us) == 0) {
        switch (us) {
            Color.white => {
                try move_list.append(Move{
                    .from = Square.E1.as_board(),
                    .to = Square.G1.as_board(),
                    .move_type = MoveType{ .castle = board.WHITE_KINGSIDE },
                });
            },
            Color.black => {
                try move_list.append(Move{
                    .from = Square.E8.as_board(),
                    .to = Square.G8.as_board(),
                    .move_type = MoveType{ .castle = board.BLACK_KINGSIDE },
                });
            },
        }
    }
}

fn pawn_moves(comptime us: Color, state: GameState, move_list: *ArrayList(Move), checkmask: Bitboard, pinmask: Pinmask) !void {
    // Terminology:
    // moving => move pawn one square
    // pushing => move pawn two squares
    // moving/pushing uses the straight pinmask, capturing the diagonal one (like a queen)
    const them = comptime us.other();
    const empty = ~state.position.occupied;
    const our_pawns = state.position.pawns(us);

    // pawn moves
    var legal_pawn_moves: Bitboard = 0;
    const straight_pinned_pawns = our_pawns & pinmask.straight;
    const unpinned_pawns = our_pawns & ~pinmask.both;
    var pinned_pawn_moves: Bitboard = undefined;
    var unpinned_pawn_moves: Bitboard = undefined;
    switch (us) {
        Color.white => {
            pinned_pawn_moves = straight_pinned_pawns >> 8 & pinmask.straight & empty; // needed later for pawn pushes
            unpinned_pawn_moves = unpinned_pawns >> 8 & empty;
        },
        Color.black => {
            pinned_pawn_moves = straight_pinned_pawns << 8 & pinmask.straight & empty; // needed later for pawn pushes
            unpinned_pawn_moves = unpinned_pawns << 8 & empty;
        },
    }
    legal_pawn_moves |= pinned_pawn_moves;
    legal_pawn_moves |= unpinned_pawn_moves;

    legal_pawn_moves &= checkmask; // prune moves that leave the king in check
    while (legal_pawn_moves != 0) : (pop_ls1b(&legal_pawn_moves)) {
        const to = get_lsb_square(legal_pawn_moves);
        switch (us) {
            Color.white => {
                try move_list.append(Move{
                    .from = to.down_one().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .quiet = PieceType.pawn },
                });
            },
            Color.black => {
                try move_list.append(Move{
                    .from = to.up_one().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .quiet = PieceType.pawn },
                });
            },
        }
    }

    // pawn pushes
    // no pinmask required here - if we were able to move then we are also able to push ^^
    switch (us) {
        Color.white => {
            var pawn_pushes: Bitboard = ((pinned_pawn_moves | unpinned_pawn_moves) & bitboard.RANK_3) >> 8 & empty & checkmask;
            while (pawn_pushes != 0) : (pop_ls1b(&pawn_pushes)) {
                const to = get_lsb_square(pawn_pushes);
                try move_list.append(Move{
                    .from = to.down_two().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType.double_push,
                });
            }
        },
        Color.black => {
            var pawn_pushes: Bitboard = ((pinned_pawn_moves | unpinned_pawn_moves) & bitboard.RANK_6) << 8 & empty & checkmask;
            while (pawn_pushes != 0) : (pop_ls1b(&pawn_pushes)) {
                const to = get_lsb_square(pawn_pushes);
                try move_list.append(Move{
                    .from = to.up_two().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType.double_push,
                });
            }
        },
    }

    // pawn captures
    var left_captures: Bitboard = 0;
    var right_captures: Bitboard = 0;

    const diag_pinned_pawns = our_pawns & pinmask.diagonal;
    left_captures |= pawn_attacks_left(us, diag_pinned_pawns) & pinmask.diagonal;
    left_captures |= pawn_attacks_left(us, unpinned_pawns);

    right_captures |= pawn_attacks_right(us, diag_pinned_pawns) & pinmask.diagonal;
    right_captures |= pawn_attacks_right(us, unpinned_pawns);

    left_captures &= state.position.occupied_by(them);
    right_captures &= state.position.occupied_by(them);
    left_captures &= checkmask;
    right_captures &= checkmask;

    while (left_captures != 0) : (pop_ls1b(&left_captures)) {
        const to = get_lsb_square(left_captures);
        switch (us) {
            Color.white => {
                try move_list.append(Move{
                    .from = to.down_right().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .capture = PieceType.pawn },
                });
            },
            Color.black => {
                try move_list.append(Move{
                    .from = to.up_right().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .capture = PieceType.pawn },
                });
            },
        }
    }

    while (right_captures != 0) : (pop_ls1b(&right_captures)) {
        const to = get_lsb_square(right_captures);
        switch (us) {
            Color.white => {
                try move_list.append(Move{
                    .from = to.down_left().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .capture = PieceType.pawn },
                });
            },
            Color.black => {
                try move_list.append(Move{
                    .from = to.up_left().as_board(),
                    .to = to.as_board(),
                    .move_type = MoveType{ .capture = PieceType.pawn },
                });
            },
        }
    }

    // en passant
    if (state.board_rights.en_passant) |ep_square| {
        // straight pinned pawns can never take en-passant
        var ep_attackers = pawn_attacks(them, ep_square.as_board()) & our_pawns & ~pinmask.straight;

        while (ep_attackers != 0) : (pop_ls1b(&ep_attackers)) {
            const from = get_lsb_square(ep_attackers).as_board();

            if (from & pinmask.diagonal == 0 or (from & pinmask.diagonal != 0 and ep_square.as_board() & pinmask.diagonal != 0)) {
                // make sure king is not left in check
                const straight_sliders = state.position.rooks(them) | state.position.queens(them);
                const king = bitboard.get_lsb_square(state.position.king(us));
                switch (us) {
                    Color.white => {
                        const mask = from | ep_square.down_one().as_board();
                        if (rook_attacks(king, state.position.occupied ^ mask) & straight_sliders != 0) {
                            break;
                        }
                    },
                    Color.black => {
                        const mask = from | ep_square.down_one().as_board();
                        if (rook_attacks(king, state.position.occupied ^ mask) & straight_sliders != 0) {
                            break;
                        }
                    },
                }
                try move_list.append(Move{
                    .from = from,
                    .to = ep_square.as_board(),
                    .move_type = MoveType.en_passant,
                });
            }
        }
    }
}

test "generate pinmask" {
    const expectEqual = std.testing.expectEqual;
    const parse_fen = board.parse_fen;

    // contains straight pins, diagonal pins and various setups
    // that look like pins, but actually aren't
    const state = (try parse_fen("1b6/4P1P1/4r3/rP2K3/8/2P5/8/b7 w - - 0 1")).state;
    const pins = generate_pinmask(Color.white, state.position);

    try expectEqual(@as(Bitboard, 0x10204080f000000), pins.both);
    try expectEqual(@as(Bitboard, 0xf000000), pins.straight);
    try expectEqual(@as(Bitboard, 0x102040800000000), pins.diagonal);
}

test "checkmask generation" {
    const expectEqual = std.testing.expectEqual;
    const parse_fen = board.parse_fen;

    // Simple check, only blocking/capturing the checking piece is allowed
    const simple = (try parse_fen("8/1q5b/8/5P2/4K3/8/8/8 w - - 0 1")).state;
    try expectEqual(@as(Bitboard, 0x8040200), generate_checkmask(Color.white, simple.position));

    // Double check - no moves (except king moves) allowed
    const double = (try parse_fen("8/8/5q2/8/1p6/2K5/8/8 w - - 0 1")).state;
    try expectEqual(@as(Bitboard, 0), generate_checkmask(Color.white, double.position));

    // No check, all moves allowed
    const no_check = (try parse_fen("8/8/8/3K4/8/8/8/8 w - - 0 1")).state;
    try expectEqual(~@as(Bitboard, 0), generate_checkmask(Color.white, no_check.position));
}

test "en passant" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const parse_fen = board.parse_fen;

    var move_list = ArrayList(Move).init(test_allocator);
    defer move_list.deinit();

    // https://lichess.org/analysis/fromPosition/1K5k/8/8/1Pp5/8/8/8/1r6_w_-_c6_1_1
    // white cannot take en-passant because the pawn is pinned to the king
    const straight_pin = (try parse_fen("1K5k/8/8/1Pp5/8/8/8/1r6 w - c6 1 1")).state;

    try generate_moves(Color.white, straight_pin, &move_list);

    for (move_list.items) |move| {
        try expect(move.move_type != MoveType.en_passant);
    }

    move_list.clearAndFree();

    // https://lichess.org/analysis/fromPosition/4q2k/8/8/1Pp5/K7/8/8/8_w_-_c6_1_1
    // white can take, despite the pawn being pinned
    const diagonal_pin = (try parse_fen("4q2k/8/8/1Pp5/K7/8/8/8 w - c6 1 1")).state;

    try generate_moves(Color.white, diagonal_pin, &move_list);

    var found_en_passant = false;
    for (move_list.items) |move| {
        if (move.move_type == MoveType.en_passant) {
            found_en_passant = true;
            break;
        }
    }
    try expect(found_en_passant);

    move_list.clearAndFree();

    // https://lichess.org/analysis/standard/7k/8/8/KPp4r/8/8/8/8_w_-_c6_1_1
    // white cannot take en-passant because that would leave the king check
    const tricky_pin = (try parse_fen("7k/8/8/KPp4r/8/8/8/8 w - c6 1 1")).state;

    try generate_moves(Color.white, tricky_pin, &move_list);

    for (move_list.items) |move| {
        try expect(move.move_type != MoveType.en_passant);
    }
}
