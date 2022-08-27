//! Defines the state of a chess board including a FEN parser

const std = @import("std");
const bitboard = @import("bitboard.zig");
const bitops = @import("bitops.zig");

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

pub const Piece = enum(u4) {
    white_pawn,
    white_knight,
    white_bishop,
    white_rook,
    white_queen,
    white_king,
    black_pawn,
    black_knight,
    black_bishop,
    black_rook,
    black_queen,
    black_king,
    no_piece,

    pub inline fn new(color: Color, piece_type: PieceType) Piece {
        return @intToEnum(Piece, @enumToInt(color) * @as(u4, 6) + @enumToInt(piece_type));
    }

    pub inline fn is_white(self: *const Piece) bool {
        return @enumToInt(self.*) < @enumToInt(Piece.black_pawn);
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
    bb_position: [12]u64,
    pieces: [64]Piece,
    occupancies: [3]u64,
    active_color: Color,
    castling_rights: CastlingRights,
    en_passant: ?u6,
    halfmove_counter: u8,
    fullmove_counter: u8,

    fn new() Board {
        return Board{
            .bb_position = [1]u64{0} ** 12,
            .pieces = [1]Piece{Piece.no_piece} ** 64,
            .occupancies = [1]u64{0} ** 3,
            .active_color = Color.white,
            .castling_rights = CastlingRights.none(),
            .en_passant = null,
            .halfmove_counter = 0,
            .fullmove_counter = 0,
        };
    }

    pub fn put_piece(self: *Board, piece: Piece, square: u6) void {
        const mask = @as(u64, 1) << square;
        self.bb_position[@enumToInt(piece)] |= mask;
        self.occupancies[@boolToInt(!piece.is_white())] |= mask;
        self.occupancies[@enumToInt(Color.both)] |= mask;
        self.pieces[square] = piece;
    }

    /// Clearing an already empty square is undefined behaviour
    pub fn clear(self: *Board, square: u6) void {
        const piece = self.pieces[square];
        std.debug.assert(piece != Piece.no_piece);
        const mask = @as(u64, 1) << square;

        self.pieces[square] = Piece.no_piece;
        self.bb_position[@enumToInt(piece)] ^= mask;
        self.occupancies[@enumToInt(Color.both)] ^= mask;
        self.occupancies[@boolToInt(!piece.is_white)] ^= mask;
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
                    'K' => board.put_piece(Piece.white_king, rank * 8 + file),
                    'Q' => board.put_piece(Piece.white_queen, rank * 8 + file),
                    'R' => board.put_piece(Piece.white_rook, rank * 8 + file),
                    'B' => board.put_piece(Piece.white_bishop, rank * 8 + file),
                    'N' => board.put_piece(Piece.white_knight, rank * 8 + file),
                    'P' => board.put_piece(Piece.white_pawn, rank * 8 + file),
                    'k' => board.put_piece(Piece.black_king, rank * 8 + file),
                    'q' => board.put_piece(Piece.black_queen, rank * 8 + file),
                    'r' => board.put_piece(Piece.black_rook, rank * 8 + file),
                    'b' => board.put_piece(Piece.black_bishop, rank * 8 + file),
                    'n' => board.put_piece(Piece.black_knight, rank * 8 + file),
                    'p' => board.put_piece(Piece.black_pawn, rank * 8 + file),
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
                const c = switch (self.pieces[square]) {
                    Piece.white_pawn => "P", // white pawn
                    Piece.white_knight => "N", // white knight
                    Piece.white_bishop => "B",
                    Piece.white_rook => "R",
                    Piece.white_queen => "Q",
                    Piece.white_king => "K",
                    Piece.black_pawn => "p",
                    Piece.black_knight => "n",
                    Piece.black_bishop => "b",
                    Piece.black_rook => "r",
                    Piece.black_queen => "q",
                    Piece.black_king => "k",
                    Piece.no_piece => ".",
                };
                std.debug.print("{s} ", .{c});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n   a b c d e f g h\n", .{});
    }

    // /// Return a bitboard marking all the squares attacked(or guarded) by a piece of a certain color
    // /// Note that the opponent king is effectively considered to be nonexistent, as he cannot move
    // /// to squares that are x-rayed by an opponent slider piece.
    // /// So result is "a bitboard marking all positions that the opponent king cannot move to".
    // pub fn king_unsafe_squares(self: *Board, opponent_color: Color) u64 {
    //     var attacked: u64 = 0;
    //     const my_color = opponent_color.other();
    //     const ALL_WITHOUT_KING = self.get_occupancies(Color.both) ^ self.get_bitboard(Piece.new(my_color, PieceType.king));

    //     // pawns
    //     if (by_white) {
    //         attacked |= bitboard.white_pawn_attacks_left(self.position[opponent_color][PAWN]);
    //         attacked |= bitboard.white_pawn_attacks_right(self.position[opponent_color][PAWN]);
    //     } else {
    //         attacked |= bitboard.black_pawn_attacks_left(self.position[opponent_color][PAWN]);
    //         attacked |= bitboard.black_pawn_attacks_right(self.position[opponent_color][PAWN]);
    //     }

    //     // knights
    //     var knights = self.position[opponent_color][KNIGHT];
    //     while (knights != 0) : (bitops.pop_ls1b(&knights)) {
    //         const index = bitops.ls1b_index(knights);
    //         attacked |= bitboard.knight_attacks(index);
    //     }

    //     // bishops
    //     var bishops = self.position[opponent_color][BISHOP];
    //     while (bishops != 0) : (bitops.pop_ls1b(&bishops)) {
    //         const index = bitops.ls1b_index(bishops);
    //         attacked |= bitboard.bishop_attacks(index, ALL_WITHOUT_KING);
    //     }

    //     // rooks
    //     var rooks = self.position[opponent_color][ROOK];
    //     while (rooks != 0) : (bitops.pop_ls1b(&rooks)) {
    //         const index = bitops.ls1b_index(rooks);
    //         attacked |= bitboard.rook_attacks(index, ALL_WITHOUT_KING);
    //     }

    //     // queens
    //     var queens = self.position[opponent_color][QUEEN];
    //     while (queens != 0) : (bitops.pop_ls1b(&queens)) {
    //         const index = bitops.ls1b_index(queens);
    //         attacked |= bitboard.queen_attacks(index, ALL_WITHOUT_KING);
    //     }

    //     // king(s)
    //     var kings = self.position[opponent_color][KING];
    //     while (kings != 0) : (bitops.pop_ls1b(&kings)) {
    //         const index = bitops.ls1b_index(kings);
    //         attacked |= bitboard.king_attacks(index);
    //     }
    //     return attacked;
    // }
};
