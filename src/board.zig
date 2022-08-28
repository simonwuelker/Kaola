//! Defines the state of a chess board including a FEN parser

const std = @import("std");
const bitboard = @import("bitboard.zig");
const bitops = @import("bitops.zig");
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const MoveType = movegen.MoveType;

// Chess pieces
const WHITE_KING = Piece.new(Color.white, PieceType.king);
const WHITE_QUEEN = Piece.new(Color.white, PieceType.queen);
const WHITE_ROOK = Piece.new(Color.white, PieceType.rook);
const WHITE_BISHOP = Piece.new(Color.white, PieceType.bishop);
const WHITE_KNIGHT = Piece.new(Color.white, PieceType.knight);
const WHITE_PAWN = Piece.new(Color.white, PieceType.pawn);
const BLACK_KING = Piece.new(Color.black, PieceType.king);
const BLACK_QUEEN = Piece.new(Color.black, PieceType.queen);
const BLACK_ROOK = Piece.new(Color.black, PieceType.rook);
const BLACK_BISHOP = Piece.new(Color.black, PieceType.bishop);
const BLACK_KNIGHT = Piece.new(Color.black, PieceType.knight);
const BLACK_PAWN = Piece.new(Color.black, PieceType.pawn);

const Square = enum(u6) {
    A8,
    B8,
    C8,
    D8,
    E8,
    F8,
    G8,
    H8,
    A7,
    B7,
    C7,
    D7,
    E7,
    F7,
    G7,
    H7,
    A6,
    B6,
    C6,
    D6,
    E6,
    F6,
    G6,
    H6,
    A5,
    B5,
    C5,
    D5,
    E5,
    F5,
    G5,
    H5,
    A4,
    B4,
    C4,
    D4,
    E4,
    F4,
    G4,
    H4,
    A3,
    B3,
    C3,
    D3,
    E3,
    F3,
    G3,
    H3,
    A2,
    B2,
    C2,
    D2,
    E2,
    F2,
    G2,
    H2,
    A1,
    B1,
    C1,
    D1,
    E1,
    F1,
    G1,
    H1,
};

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

pub const Piece = struct {
    color: Color,
    piece_type: PieceType,

    pub inline fn new(color: Color, piece_type: PieceType) Piece {
        return Piece{
            .color = color,
            .piece_type = piece_type,
        };
    }
};

pub const Color = enum(u2) {
    white,
    black,
    both,

    pub inline fn other(self: *const Color) Color {
        return @intToEnum(Color, 1 - @enumToInt(self.*));
    }
};

pub const CastlingRights = packed struct {
    /// Bit indicating whether or not white can castle kingside
    white_kingside: bool,
    /// Bit indicating whether or not white can castle queenside
    white_queenside: bool,
    /// Bit indicating whether or not black can castle kingside
    black_kingside: bool,
    /// Bit indicating whether or not black can castle queenside
    black_queenside: bool,

    pub fn none() CastlingRights {
        return CastlingRights{
            .white_kingside = false,
            .white_queenside = false,
            .black_kingside = false,
            .black_queenside = false,
        };
    }
};

/// Errors that can occur while parsing a FEN string
const FenParseError = error{
    MissingField,
    InvalidPosition,
    InvalidActiveSide,
    InvalidCastlingRights,
    InvalidEnPassant,
    InvalidHalfMoveCounter,
    InvalidFullMoveCounter,
};

/// Return the square name (e.g 0 becomes "a8")
pub fn square_name(square: u6) [2]u8 {
    var name: [2]u8 = undefined;
    name[0] = @intCast(u8, square % 8) + 'a';
    name[1] = '8' - @intCast(u8, square / 8);
    return name;
}

pub const Board = struct {
    bb_position: [2][6]u64,
    pieces: [64]?Piece,
    occupancies: [3]u64,
    active_color: Color,
    castling_rights: CastlingRights,
    en_passant: ?u6,
    halfmove_counter: u8,
    fullmove_counter: u8,

    fn new() Board {
        return Board{
            .bb_position = [1][6]u64{[1]u64{0} ** 6} ** 2,
            .pieces = [1]?Piece{null} ** 64,
            .occupancies = [1]u64{0} ** 3,
            .active_color = Color.white,
            .castling_rights = CastlingRights.none(),
            .en_passant = null,
            .halfmove_counter = 0,
            .fullmove_counter = 0,
        };
    }

    pub fn place_piece(self: *Board, piece: Piece, square: u6) void {
        const mask = @as(u64, 1) << square;
        self.bb_position[@enumToInt(piece.color)][@enumToInt(piece.piece_type)] |= mask;
        self.occupancies[@enumToInt(piece.color)] |= mask;
        self.occupancies[@enumToInt(Color.both)] |= mask;
        self.pieces[square] = piece;
    }

    /// Clearing an already empty square is undefined behaviour
    pub fn take_piece(self: *Board, square: u6) Piece {
        const piece = self.pieces[square] orelse unreachable;
        const mask = @as(u64, 1) << square;

        self.pieces[square] = null;
        self.bb_position[@enumToInt(piece.color)][@enumToInt(piece.piece_type)] ^= mask;
        self.occupancies[@enumToInt(Color.both)] ^= mask;
        self.occupancies[@enumToInt(piece.color)] ^= mask;
        return piece;
    }

    /// Create a new board with the starting position
    pub fn starting_position() Board {
        return Board.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
    }

    pub inline fn get_bitboard(self: *const Board, piece: Piece) u64 {
        return self.bb_position[@enumToInt(piece.color)][@enumToInt(piece.piece_type)];
    }

    pub inline fn get_occupancies(self: *const Board, color: Color) u64 {
        return self.occupancies[@enumToInt(color)];
    }

    /// Parse the board state from a FEN string
    pub fn from_fen(fen: []const u8) FenParseError!Board {
        var board = Board.new();
        var parts = std.mem.split(u8, fen, " ");

        // Parse the board position
        const fen_position = parts.next().?;
        var ranks = std.mem.split(u8, fen_position, "/");
        var rank: u6 = 0;
        while (ranks.next()) |entry| {
            var file: u6 = 0;
            for (entry) |c| {
                switch (c) {
                    'K' => board.place_piece(WHITE_KING, rank * 8 + file),
                    'Q' => board.place_piece(WHITE_QUEEN, rank * 8 + file),
                    'R' => board.place_piece(WHITE_ROOK, rank * 8 + file),
                    'B' => board.place_piece(WHITE_BISHOP, rank * 8 + file),
                    'N' => board.place_piece(WHITE_KNIGHT, rank * 8 + file),
                    'P' => board.place_piece(WHITE_PAWN, rank * 8 + file),
                    'k' => board.place_piece(BLACK_KING, rank * 8 + file),
                    'q' => board.place_piece(BLACK_QUEEN, rank * 8 + file),
                    'r' => board.place_piece(BLACK_ROOK, rank * 8 + file),
                    'b' => board.place_piece(BLACK_BISHOP, rank * 8 + file),
                    'n' => board.place_piece(BLACK_KNIGHT, rank * 8 + file),
                    'p' => board.place_piece(BLACK_PAWN, rank * 8 + file),
                    '1'...'8' => file += @intCast(u3, c - '1'),
                    else => return FenParseError.InvalidPosition,
                }
                file += 1;
            }
            if (file != 8) return FenParseError.InvalidPosition;
            rank += 1;
        }
        if (rank != 8) return FenParseError.InvalidPosition;

        // get the active side
        const fen_active_side = parts.next().?;
        std.debug.assert(fen_active_side.len == 1);
        board.active_color = switch (fen_active_side[0]) {
            'w' => Color.white,
            'b' => Color.black,
            else => return FenParseError.InvalidActiveSide,
        };

        // get the castling rights
        const fen_castling_rights = parts.next().?;
        board.castling_rights = CastlingRights.none();
        for (fen_castling_rights) |c| {
            switch (c) {
                'K' => board.castling_rights.white_kingside = true,
                'Q' => board.castling_rights.white_queenside = true,
                'k' => board.castling_rights.black_kingside = true,
                'q' => board.castling_rights.black_queenside = true,
                '-' => break,
                else => return FenParseError.InvalidCastlingRights,
            }
        }

        // get the en passant square
        const fen_en_passant = parts.next().?;
        board.en_passant = null;
        if (!std.mem.eql(u8, fen_en_passant, "-")) {
            board.en_passant = @intCast(u6, fen_en_passant[0] - 'a' + (fen_en_passant[1] - '1') * 8);
        }

        // get halfmove counter
        const fen_halfmove_counter = parts.next().?;
        board.halfmove_counter = std.fmt.parseUnsigned(u8, fen_halfmove_counter, 10) catch return FenParseError.InvalidHalfMoveCounter;

        // get fullmove counter
        const fen_fullmove_counter = parts.next().?;
        board.fullmove_counter = std.fmt.parseUnsigned(u8, fen_fullmove_counter, 10) catch return FenParseError.InvalidFullMoveCounter;

        return board;
    }

    /// Print the formatted position to the terminal.
    /// This assumes that the position is valid, i.e no two pieces occupy the same position
    pub fn print(self: *const Board) void {
        var i: u6 = 0;
        while (i < 8) : (i += 1) {
            std.debug.print("{d}  ", .{8 - i});
            var j: u6 = 0;
            while (j < 8) : (j += 1) {
                const square = i * 8 + j;

                var c: u8 = '.';
                if (self.pieces[square]) |piece| {
                    c = switch (piece.piece_type) {
                        PieceType.pawn => 'P',
                        PieceType.knight => 'N',
                        PieceType.bishop => 'B',
                        PieceType.rook => 'R',
                        PieceType.queen => 'Q',
                        PieceType.king => 'K',
                    };
                    // lowercase for black pieces
                    if (piece.color == Color.black) c += 0x20;
                }
                std.debug.print("{c} ", .{c});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n   a b c d e f g h\n", .{});
    }

    pub fn apply(self: *Board, move: Move) void {
        // contains a few if cases but only on rare move types (castling/en passant)
        // so it should be fine
        switch (move.move_type) {
            MoveType.QUIET => {
                self.place_piece(self.take_piece(move.from), move.to);
            },
            MoveType.CAPTURE => {
                _ = self.take_piece(move.to);
                self.place_piece(self.take_piece(move.from), move.to);
            },
            MoveType.DOUBLE_PUSH => {
                self.place_piece(self.take_piece(move.from), move.to);
                self.en_passant = move.to;
                self.active_color = self.active_color.other();
                return; // so we don't hit the en passant reset after the switch
            },
            MoveType.CASTLE_SHORT => {
                switch (self.active_color) {
                    Color.white => {
                        self.place_piece(self.take_piece(@enumToInt(Square.E1)), @enumToInt(Square.G1));
                        self.place_piece(self.take_piece(@enumToInt(Square.H1)), @enumToInt(Square.F1));
                    },
                    Color.black => {
                        self.place_piece(self.take_piece(@enumToInt(Square.E8)), @enumToInt(Square.G8));
                        self.place_piece(self.take_piece(@enumToInt(Square.H8)), @enumToInt(Square.F8));
                    },
                    else => unreachable,
                }
            },
            MoveType.CASTLE_LONG => {
                switch (self.active_color) {
                    Color.white => {
                        self.place_piece(self.take_piece(@enumToInt(Square.E1)), @enumToInt(Square.C1));
                        self.place_piece(self.take_piece(@enumToInt(Square.A1)), @enumToInt(Square.D1));
                    },
                    Color.black => {
                        self.place_piece(self.take_piece(@enumToInt(Square.E8)), @enumToInt(Square.C8));
                        self.place_piece(self.take_piece(@enumToInt(Square.A8)), @enumToInt(Square.D8));
                    },
                    else => unreachable,
                }
            },
            MoveType.EN_PASSANT => {
                switch (self.active_color) {
                    Color.white => {
                        self.place_piece(self.take_piece(move.from), move.to);
                        _ = self.take_piece(move.to + 8);
                    },
                    Color.black => {
                        self.place_piece(self.take_piece(@enumToInt(Square.E8)), @enumToInt(Square.C8));
                        _ = self.take_piece(move.to - 8);
                    },
                    else => unreachable,
                }
            },
            MoveType.PROMOTE_KNIGHT => {
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.knight;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.PROMOTE_BISHOP => {
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.bishop;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.PROMOTE_ROOK => {
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.rook;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.PROMOTE_QUEEN => {
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.queen;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.CAPTURE_PROMOTE_KNIGHT => {
                _ = self.take_piece(move.to);
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.knight;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.CAPTURE_PROMOTE_BISHOP => {
                _ = self.take_piece(move.to);
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.bishop;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.CAPTURE_PROMOTE_ROOK => {
                _ = self.take_piece(move.to);
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.rook;
                self.place_piece(promoting_piece, move.to);
            },
            MoveType.CAPTURE_PROMOTE_QUEEN => {
                _ = self.take_piece(move.to);
                var promoting_piece = self.take_piece(move.from);
                promoting_piece.piece_type = PieceType.queen;
                self.place_piece(promoting_piece, move.to);
            },
        }
        self.active_color = self.active_color.other();
        self.en_passant = null;
    }

    /// Return a bitboard marking all the squares attacked(or guarded) by a piece of a certain color
    /// Note that the king is effectively considered to be nonexistent, as he cannot move
    /// to squares that are x-rayed by an opponent slider piece.
    /// So result is "a bitboard marking all positions that the opponent king cannot move to".
    pub fn king_unsafe_squares(self: *const Board) u64 {
        var attacked: u64 = 0;
        const us = self.active_color;
        const them = us.other();
        const ALL_WITHOUT_KING = self.get_occupancies(Color.both) ^ self.get_bitboard(Piece.new(us, PieceType.king));

        // pawns
        const opponent_pawns = self.get_bitboard(Piece.new(them, PieceType.pawn));
        if (them == Color.white) {
            attacked |= bitboard.white_pawn_attacks(opponent_pawns);
        } else {
            attacked |= bitboard.black_pawn_attacks(opponent_pawns);
        }

        // knights
        var knights = self.get_bitboard(Piece.new(them, PieceType.knight));
        while (knights != 0) : (bitops.pop_ls1b(&knights)) {
            const square = bitboard.get_lsb_square(knights);
            attacked |= bitboard.knight_attacks(square);
        }

        // bishops
        var diag_sliders = self.get_bitboard(Piece.new(them, PieceType.bishop)) | self.get_bitboard(Piece.new(them, PieceType.queen));
        while (diag_sliders != 0) : (bitops.pop_ls1b(&diag_sliders)) {
            const square = bitboard.get_lsb_square(diag_sliders);
            attacked |= bitboard.bishop_attacks(square, ALL_WITHOUT_KING);
        }

        // rooks
        var straight_sliders = self.get_bitboard(Piece.new(them, PieceType.rook)) | self.get_bitboard(Piece.new(them, PieceType.queen));
        while (straight_sliders != 0) : (bitops.pop_ls1b(&straight_sliders)) {
            const square = bitboard.get_lsb_square(straight_sliders);
            attacked |= bitboard.rook_attacks(square, ALL_WITHOUT_KING);
        }

        // king(s)
        var kings = self.get_bitboard(Piece.new(them, PieceType.king));
        while (kings != 0) : (bitops.pop_ls1b(&kings)) {
            const square = bitboard.get_lsb_square(kings);
            attacked |= bitboard.king_attacks(square);
        }
        return attacked;
    }
};
