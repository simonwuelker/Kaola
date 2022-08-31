//! Defines the state of a chess board including a FEN parser

const std = @import("std");
const bitboard = @import("bitboard.zig");
const bitops = @import("bitops.zig");
const movegen = @import("movegen.zig");
const zobrist = @import("zobrist.zig");
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

// Squares on a chess board
pub const Square = enum(u6) {
    // zig fmt: off
    A8, B8, C8, D8, E8, F8, G8, H8,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A1, B1, C1, D1, E1, F1, G1, H1,
    // zig fmt: on

    pub inline fn from_str(str: []const u8) Square {
        return @intToEnum(Square, ('8' - str[1]) * 8 + (str[0] - 'a'));
    }

    pub inline fn as_board(self: *const Square) u64 {
        return @as(u64, 1) << @enumToInt(self.*);
    }

    pub inline fn to_str(self: *const Square) [:0]const u8 {
        return SQUARE_NAME[@enumToInt(self.*)];
    }

    pub inline fn file(self: *const Square) u3 {
        return @intCast(u3, @enumToInt(self.*) & 0b111);
    }

    pub inline fn rank(self: *const Square) u3 {
        return @intCast(u3, @enumToInt(self.*) >> 3);
    }

    pub inline fn down_one(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 8);
    }

    pub inline fn up_one(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 8);
    }

    pub inline fn down_two(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 16);
    }

    pub inline fn up_two(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 16);
    }

    pub inline fn down_left(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 7);
    }

    pub inline fn down_right(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) + 9);
    }
};

const SQUARE_NAME = [64][:0]const u8{
    "a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8",
    "a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7",
    "a6", "b6", "c6", "d6", "e6", "f6", "g6", "h6",
    "a5", "b5", "c5", "d5", "e5", "f5", "g5", "h5",
    "a4", "b4", "c4", "d4", "e4", "f4", "g4", "h4",
    "a3", "b3", "c3", "d3", "e3", "f3", "g3", "h3",
    "a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2",
    "a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1",
};

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,

    /// Build a piece with the desired color
    pub fn color(self: *const PieceType, desired_color: Color) Piece {
        std.debug.assert(desired_color != Color.both);
        return @intToEnum(Piece, @as(u4, @enumToInt(self.*)) << 1 | @truncate(u1, @enumToInt(desired_color)));
    }
};

/// Last bit represents piece color, first three bits piece type
pub const Piece = enum(u4) {
    white_pawn = 0b0000,
    black_pawn = 0b0001,
    white_knight = 0b0010,
    black_knight = 0b0011,
    white_bishop = 0b0100,
    black_bishop = 0b0101,
    white_rook = 0b0110,
    black_rook = 0b0111,
    white_queen = 0b1000,
    black_queen = 0b1001,
    white_king = 0b1010,
    black_king = 0b1011,

    /// Get the piece color
    pub fn color(self: *const Piece) Color {
        return @intToEnum(Color, @enumToInt(self.*) & 1);
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

pub const Board = struct {
    bb_position: [12]u64,
    pieces: [64]?Piece,
    occupancies: [3]u64,
    active_color: Color,
    castling_rights: CastlingRights,
    en_passant: ?u6,
    halfmove_counter: u8,
    fullmove_counter: u8,
    zobrist_hash: u64,

    fn new() Board {
        return Board{
            .bb_position = [1]u64{0} ** 12,
            .pieces = [1]?Piece{null} ** 64,
            .occupancies = [1]u64{0} ** 3,
            .active_color = Color.white,
            .castling_rights = CastlingRights.none(),
            .en_passant = null,
            .halfmove_counter = 0,
            .fullmove_counter = 0,
            .zobrist_hash = 0,
        };
    }

    pub fn place_piece(self: *Board, piece: Piece, square: u6) void {
        const mask = @as(u64, 1) << square;
        self.bb_position[@enumToInt(piece)] |= mask;
        self.occupancies[@enumToInt(piece.color())] |= mask;
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
        return self.bb_position[@enumToInt(piece)];
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
                    'K' => board.place_piece(Piece.white_king, rank * 8 + file),
                    'Q' => board.place_piece(Piece.white_queen, rank * 8 + file),
                    'R' => board.place_piece(Piece.white_rook, rank * 8 + file),
                    'B' => board.place_piece(Piece.white_bishop, rank * 8 + file),
                    'N' => board.place_piece(Piece.white_knight, rank * 8 + file),
                    'P' => board.place_piece(Piece.white_pawn, rank * 8 + file),
                    'k' => board.place_piece(Piece.black_king, rank * 8 + file),
                    'q' => board.place_piece(Piece.black_queen, rank * 8 + file),
                    'r' => board.place_piece(Piece.black_rook, rank * 8 + file),
                    'b' => board.place_piece(Piece.black_bishop, rank * 8 + file),
                    'n' => board.place_piece(Piece.black_knight, rank * 8 + file),
                    'p' => board.place_piece(Piece.black_pawn, rank * 8 + file),
                    '1'...'8' => file += @intCast(u3, c - '1'),
                    else => {
                        return FenParseError.InvalidPosition;
                    },
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
                    c = switch (piece) {
                        Piece.white_pawn => 'P',
                        Piece.white_knight => 'N',
                        Piece.white_bishop => 'B',
                        Piece.white_rook => 'R',
                        Piece.white_queen => 'Q',
                        Piece.white_king => 'K',
                        Piece.black_pawn => 'p',
                        Piece.black_knight => 'n',
                        Piece.black_bishop => 'b',
                        Piece.black_rook => 'r',
                        Piece.black_queen => 'q',
                        Piece.black_king => 'k',
                    };
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
        const ALL_WITHOUT_KING = self.get_occupancies(Color.both) ^ self.get_bitboard(PieceType.king.color(us));

        // pawns
        const opponent_pawns = self.get_bitboard(PieceType.pawn.color(them));
        if (them == Color.white) {
            attacked |= bitboard.white_pawn_attacks(opponent_pawns);
        } else {
            attacked |= bitboard.black_pawn_attacks(opponent_pawns);
        }

        // knights
        var knights = self.get_bitboard(PieceType.knight.color(them));
        while (knights != 0) : (bitops.pop_ls1b(&knights)) {
            const square = bitboard.get_lsb_square(knights);
            attacked |= bitboard.knight_attacks(square.as_board());
        }

        // bishops
        var diag_sliders = self.get_bitboard(PieceType.bishop.color(them)) | self.get_bitboard(PieceType.queen.color(them));
        while (diag_sliders != 0) : (bitops.pop_ls1b(&diag_sliders)) {
            const square = bitboard.get_lsb_square(diag_sliders);
            attacked |= bitboard.bishop_attacks(square, ALL_WITHOUT_KING);
        }

        // rooks
        var straight_sliders = self.get_bitboard(PieceType.rook.color(them)) | self.get_bitboard(PieceType.queen.color(them));
        while (straight_sliders != 0) : (bitops.pop_ls1b(&straight_sliders)) {
            const square = bitboard.get_lsb_square(straight_sliders);
            attacked |= bitboard.rook_attacks(square, ALL_WITHOUT_KING);
        }

        // king(s)
        var kings = self.get_bitboard(PieceType.king.color(them));
        while (kings != 0) : (bitops.pop_ls1b(&kings)) {
            attacked |= bitboard.king_attacks(kings);
        }
        return attacked;
    }
};
