const std = @import("std");

pub const WHITE = 0;
pub const BLACK = 1;
pub const BOTH = 2;
pub const PAWN = 0;
pub const KNIGHT = 1;
pub const BISHOP = 2;
pub const ROOK = 3;
pub const QUEEN = 4;
pub const KING = 5;

/// Bit indicating whether or not white can castle kingside
pub const WHITE_KINGSIDE: u4 = 1;
/// Bit indicating whether or not white can castle queenside
pub const WHITE_QUEENSIDE: u4 = 2;
/// Bit indicating whether or not black can castle kingside
pub const BLACK_KINGSIDE: u4 = 4;
/// Bit indicating whether or not black can castle queenside
pub const BLACK_QUEENSIDE: u4 = 8;

/// Errors that can occur while parsing a FEN string
const FenParseError = error {
    MissingField,
    InvalidPosition,
    InvalidActiveSide,
    InvalidCastlingRights,
    InvalidEnPassant,
    InvalidHalfMoveCounter,
    InvalidFullMoveCounter,
};

pub fn square_name(square: u6) [2]u8 {
    var name: [2]u8 = undefined;
    name[0] = @intCast(u8, square % 8) + 'a';
    name[1] = '8' - @intCast(u8, square / 8);
    return name;
}

pub const Board = struct {
    position: [2][6]u64,
    occupancies: [3]u64,
    white_to_move: bool,
    castling_rights: u4,
    en_passant: ?u6,
    halfmove_counter: u8,
    fullmove_counter: u8,

    /// Create a new board with the starting position
    pub fn starting_position() Board {
        return Board.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
    }

    /// Parse the board state from a FEN string
    pub fn from_fen(fen: []const u8) FenParseError!Board {
        var parts = std.mem.split(u8, fen, " ");

        // Parse the board position
        const fen_position = parts.next().?;
        var bitboard_position: [2][6]u64 = [1][6]u64 { [1]u64 { 0 } ** 6 } ** 2;
        var ranks = std.mem.split(u8, fen_position, "/");
        var rank: u6 = 0;
        while (ranks.next()) |entry| {
            var file: u6 = 0;
            for (entry) |c| {
                switch (c) {
                    'K' => bitboard_position[WHITE][KING] |= @as(u64, 1) << (rank * 8 + file),
                    'k' => bitboard_position[BLACK][KING] |= @as(u64, 1) << (rank * 8 + file),
                    'Q' => bitboard_position[WHITE][QUEEN] |= @as(u64, 1) << (rank * 8 + file),
                    'q' => bitboard_position[BLACK][QUEEN] |= @as(u64, 1) << (rank * 8 + file),
                    'R' => bitboard_position[WHITE][ROOK] |= @as(u64, 1) << (rank * 8 + file),
                    'r' => bitboard_position[BLACK][ROOK] |= @as(u64, 1) << (rank * 8 + file),
                    'N' => bitboard_position[WHITE][KNIGHT] |= @as(u64, 1) << (rank * 8 + file),
                    'n' => bitboard_position[BLACK][KNIGHT] |= @as(u64, 1) << (rank * 8 + file),
                    'B' => bitboard_position[WHITE][BISHOP] |= @as(u64, 1) << (rank * 8 + file),
                    'b' => bitboard_position[BLACK][BISHOP] |= @as(u64, 1) << (rank * 8 + file),
                    'P' => bitboard_position[WHITE][PAWN] |= @as(u64, 1) << (rank * 8 + file),
                    'p' => bitboard_position[BLACK][PAWN] |= @as(u64, 1) << (rank * 8 + file),
                    '1'...'8' => file += @intCast(u3, c - '1'),
                    else => return FenParseError.InvalidPosition,
                }
                file += 1;
            }
            if (file != 8) return FenParseError.InvalidPosition;
            rank += 1;
        }
        if (rank != 8) return FenParseError.InvalidPosition;

        // Calculate the occupancies
        var occupancies: [3]u64 = undefined;
        occupancies[WHITE] = bitboard_position[WHITE][PAWN] 
            | bitboard_position[WHITE][KNIGHT] 
            | bitboard_position[WHITE][BISHOP] 
            | bitboard_position[WHITE][ROOK] 
            | bitboard_position[WHITE][QUEEN]
            | bitboard_position[WHITE][KING];
        occupancies[BLACK] = bitboard_position[BLACK][PAWN] 
            | bitboard_position[BLACK][KNIGHT] 
            | bitboard_position[BLACK][BISHOP] 
            | bitboard_position[BLACK][ROOK] 
            | bitboard_position[BLACK][QUEEN]
            | bitboard_position[BLACK][KING];
        occupancies[BOTH] = occupancies[WHITE] | occupancies[BLACK];

        // get the active side
        const fen_active_side = parts.next().?;
        std.debug.assert(fen_active_side.len == 1);
        const white_to_move = switch(fen_active_side[0]) {
            'w' => true,
            'b' => false,
            else => return FenParseError.InvalidActiveSide,
        };

        // get the castling rights
        const fen_castling_rights = parts.next().?;
        var castling_rights: u4 = 0;
        for (fen_castling_rights) |c| {
            switch (c) {
                'K' => castling_rights |= WHITE_KINGSIDE,
                'Q' => castling_rights |= WHITE_QUEENSIDE,
                'k' => castling_rights |= BLACK_KINGSIDE,
                'q' => castling_rights |= BLACK_QUEENSIDE,
                '-' => break,
                else => return FenParseError.InvalidCastlingRights,
            }
        }

        // get the en passant square
        const fen_en_passant = parts.next().?;
        var en_passant: ?u6 = null;
        if (!std.mem.eql(u8, fen_en_passant, "-")) {
            en_passant = @intCast(u6, fen_en_passant[0] - 0x61 + (fen_en_passant[1] - 0x31) * 8);
        }

        // get halfmove counter
        const fen_halfmove_counter = parts.next().?;
        const halfmove_counter = std.fmt.parseUnsigned(u8, fen_halfmove_counter, 10) catch return FenParseError.InvalidHalfMoveCounter;

        // get fullmove counter
        const fen_fullmove_counter = parts.next().?;
        const fullmove_counter = std.fmt.parseUnsigned(u8, fen_fullmove_counter, 10) catch return FenParseError.InvalidFullMoveCounter;


        return Board {
            .position = bitboard_position,
            .occupancies = occupancies,
            .white_to_move = white_to_move,
            .castling_rights = castling_rights,
            .en_passant = en_passant,
            .halfmove_counter = halfmove_counter,
            .fullmove_counter = fullmove_counter,
        };
    }

    /// Print the formatted position to the terminal.
    /// This assumes that the position is valid, i.e no two pieces occupy the same position
    pub fn print(self: *const Board) void {
        var i: u6 = 0;
        while (i < 8): (i += 1) {
            std.debug.print("{d}  ", .{8-i});
            var j: u6 = 0;
            while (j < 8): (j += 1) {
                const mask = @as(u64, 1) << (i * 8 + j);
                var count: u4 = 0;
                var c = ".";
                while (count < 12): (count += 1) {
                    if (self.position[count / 6][count % 6]  & mask != 0) {
                        c = switch (count) {
                            0 => "P",  // white pawn
                            1 => "N",  // white knight
                            2 => "B",  // white bishop
                            3 => "R",  // white rook
                            4 => "Q",  // white queen
                            5 => "K",  // white king
                            6 => "p",  // black pawn
                            7 => "n",  // black knight
                            8 => "b",  // black bishop
                            9 => "r",  // black rook
                            10 => "q", // black queen
                            11 => "k", // black king
                            else => unreachable,
                        };
                    }
                }
                std.debug.print("{s} ", .{c});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n   a b c d e f g h\n", .{});
    }
};
