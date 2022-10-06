//! Defines the state of a chess board including a FEN parser
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;
const bitops = @import("bitops.zig");

const zobrist = @import("zobrist.zig");

const generate_moves = @import("movegen.zig").generate_moves;

pub const PieceType = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

pub const Color = enum(u1) {
    white,
    black,

    const Self = @This();

    pub inline fn other(self: *const Self) Self {
        return @intToEnum(Self, 1 - @enumToInt(self.*));
    }
};

pub const Piece = enum(u4) {
    white_pawn,
    white_knight,
    white_bishop,
    white_rook,
    white_queen,
    white_king,
    black_pawn = 8,
    black_knight,
    black_bishop,
    black_rook,
    black_queen,
    black_king,
    no_piece = 15,

    const Self = @This();

    pub fn new(new_color: Color, new_type: PieceType) Self {
        return @intToEnum(Self, @intCast(u4, @enumToInt(new_color)) << 3 | @enumToInt(new_type));
    }

    pub fn color(self: *const Self) Color {
        std.debug.assert(self.* != Self.no_piece);
        return @intToEnum(Color, @enumToInt(self.*) >> 3);
    }

    pub fn piece_type(self: *const Self) PieceType {
        std.debug.assert(self.* != Self.no_piece);
        return @intToEnum(PieceType, @enumToInt(self.*) & 0b111);
    }
};

pub const CastlingRights = struct {
    /// Whether or not white can castle kingside
    white_kingside: bool,
    /// Whether or not white can castle queenside
    white_queenside: bool,
    /// Whether or not black can castle kingside
    black_kingside: bool,
    /// Whether or not black can castle queenside
    black_queenside: bool,

    const Self = @This();

    pub fn new(wk: bool, wq: bool, bk: bool, bq: bool) Self {
        return Self{
            .white_kingside = wk,
            .white_queenside = wq,
            .black_kingside = bk,
            .black_queenside = bq,
        };
    }

    pub fn initial() Self {
        return Self.new(true, true, true, true);
    }

    pub fn remove_kingside(self: *Self, comptime color: Color) void {
        switch (color) {
            Color.white => self.white_kingside = false,
            Color.black => self.black_kingside = false,
        }
    }

    pub fn remove_queenside(self: *Self, comptime color: Color) void {
        switch (color) {
            Color.white => self.white_queenside = false,
            Color.black => self.black_queenside = false,
        }
    }

    pub fn print(self: *const Self, writer: anytype) !void {
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try writer.write("| Castle | Kingside | Queenside |\n");
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try std.fmt.format(writer, "| White  |{:^10}|{:^11}|\n", .{
            self.white_kingside,
            self.white_queenside,
        });
        _ = try writer.write("+--------+----------+-----------+\n");
        _ = try std.fmt.format(writer, "| Black  |{:^10}|{:^11}|\n", .{
            self.black_kingside,
            self.black_queenside,
        });
        _ = try writer.write("+--------+----------+-----------+\n");
    }
};

pub const GameState = struct {
    active_color: Color,
    en_passant: ?Square,
    castling_rights: CastlingRights,
    position: Position,

    const Self = @This();

    /// Errors that can occur while parsing a FEN string
    const FenParseError = error{
        MissingField,
        InvalidPosition,
        InvalidActiveColor,
        InvalidCastlingRights,
        InvalidEnPassant,
        InvalidHalfMoveCounter,
        InvalidFullMoveCounter,
    };

    pub fn initial() Self {
        return Self.from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
    }

    pub fn print(self: *const Self) !void {
        const stdout = std.io.getStdOut().writer();
        try self.castling_rights.print(stdout);
        try self.position.print(stdout);
    }

    /// The move is assumed to be legal
    pub fn make_move(self: *Self, comptime active_color: Color, move: Move) MoveUndoInfo {
        // update position
        const piece = self.position.remove_piece(move.from);
        const captured = self.position.piece_at(move.to);
        const undo_info = MoveUndoInfo{
            .en_passant = self.en_passant,
            .castling_rights = self.castling_rights,
            .captured_piece = captured,
        };

        // TODO: castling, en_passant

        if (move.flags == MoveFlags.promote) {
            self.position.place_piece(Piece.new(active_color, move.promote_to()), move.to);
        } else {
            self.position.place_piece(piece, move.to);
        }

        if (piece.piece_type() == PieceType.pawn) {
            if (@enumToInt(move.from) ^ @enumToInt(move.to) == 16) {
                switch (active_color) {
                    Color.white => self.en_passant = move.get_to().down_one(),
                    Color.black => self.en_passant = move.get_to().up_one(),
                }
            }
        }

        // update castling rights
        if (move.from == Position.king_square(active_color)) {
            self.castling_rights.remove_kingside(active_color);
            self.castling_rights.remove_queenside(active_color);
            std.debug.print("BBBBBBBBBB", .{});
        } else if (move.from == Position.kingside_rook_square(active_color)) {
            self.castling_rights.remove_kingside(active_color);
        } else if (move.from == Position.queenside_rook_square(active_color)) {
            std.debug.print("AAAAAAAAAAA", .{});
            self.castling_rights.remove_queenside(active_color);
        }

        return undo_info;
    }

    pub fn undo_move(self: *Self, move: Move, undo_info: MoveUndoInfo) void {
        // todo pretty much every non-trivial move type
        const moving_piece = self.position.remove_piece(move.to);
        self.position.place_piece(moving_piece, move.from);
        if (undo_info.captured_piece) |captured_piece| {
            self.position.place_piece(captured_piece, move.to);
        }

        self.en_passant = undo_info.en_passant;
        self.castling_rights = undo_info.castling_rights;

        self.active_color = self.active_color.other();
    }

    pub fn from_fen(fen: []const u8) FenParseError!Self {
        var parts = std.mem.split(u8, fen, " ");
        const fen_position = parts.next().?;

        // parse position
        var position = Position.empty();
        var ranks = std.mem.split(u8, fen_position, "/");
        var rank: u6 = 0;
        while (ranks.next()) |entry| {
            var file: u6 = 0;
            for (entry) |c| {
                const square = @intToEnum(Square, rank * 8 + file);
                const piece = switch (c) {
                    'P' => Piece.white_pawn,
                    'N' => Piece.white_knight,
                    'B' => Piece.white_bishop,
                    'R' => Piece.white_rook,
                    'Q' => Piece.white_queen,
                    'K' => Piece.white_king,
                    'p' => Piece.black_pawn,
                    'n' => Piece.black_knight,
                    'b' => Piece.black_bishop,
                    'r' => Piece.black_rook,
                    'q' => Piece.black_queen,
                    'k' => Piece.black_king,
                    '1'...'8' => {
                        file += @intCast(u4, c - '0');
                        continue;
                    },
                    else => {
                        return FenParseError.InvalidPosition;
                    },
                };
                position.place_piece(piece, square);
                file += 1;
            }
            if (file != 8) return FenParseError.InvalidPosition;
            rank += 1;
        }
        if (rank != 8) return FenParseError.InvalidPosition;

        const active_color_fen = parts.next().?;
        var active_color: Color = undefined;
        if (std.mem.eql(u8, active_color_fen, "w")) {
            active_color = Color.white;
        } else if (std.mem.eql(u8, active_color_fen, "b")) {
            active_color = Color.black;
        } else {
            return FenParseError.InvalidActiveColor;
        }

        const castling_fen = parts.next().?;
        var white_kingside = false;
        var white_queenside = false;
        var black_kingside = false;
        var black_queenside = false;

        for (castling_fen) |c| {
            switch (c) {
                'K' => white_kingside = true,
                'Q' => white_queenside = true,
                'k' => black_kingside = true,
                'q' => black_queenside = true,
                '-' => break,
                else => return FenParseError.InvalidCastlingRights,
            }
        }

        const en_passant_fen = parts.next().?;
        var en_passant: ?Square = null;
        if (!std.mem.eql(u8, en_passant_fen, "-")) {
            en_passant = Square.from_str(en_passant_fen);
        }
        const castling_rights = CastlingRights{
            .white_kingside = white_kingside,
            .white_queenside = white_queenside,
            .black_kingside = black_kingside,
            .black_queenside = black_queenside,
        };

        return Self{ .active_color = active_color, .en_passant = en_passant, .position = position, .castling_rights = castling_rights };
    }

    pub fn can_castle_kingside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.castling_rights.white_kingside,
            Color.black => return self.castling_rights.black_kingside,
        }
    }

    pub fn can_castle_queenside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.castling_rights.white_queenside,
            Color.black => return self.castling_rights.black_queenside,
        }
    }
};

pub const MoveFlags = enum(u2) {
    normal,
    en_passant,
    castling,
    promote,
};

pub const Move = packed struct(u16) {
    from: Square,
    to: Square,
    // Only 4 of the 6 pieces can be "promoted into"
    promotion_target: u2 = 0,
    flags: MoveFlags = MoveFlags.normal,

    const Self = @This();

    pub inline fn get_from(self: *const Self) Square {
        return self.from;
    }

    pub inline fn get_to(self: *const Self) Square {
        return self.to;
    }

    pub fn promote_to(self: *const Self) PieceType {
        std.debug.assert(self.flags == MoveFlags.promote);
        return @intToEnum(PieceType, self.promotion_target + @enumToInt(PieceType.knight));
    }

    /// Caller owns returned memory
    pub fn to_str(self: Self, allocator: Allocator) ![]const u8 {
        // Promotions need 5 bytes
        if (self.flags == MoveFlags.promote) {
            var str = try allocator.alloc(u8, 5);
            std.mem.copy(u8, str[0..2], self.get_from().to_str());
            std.mem.copy(u8, str[2..4], self.get_to().to_str());
            switch (self.promote_to()) {
                PieceType.knight => str[4] = 'n',
                PieceType.bishop => str[4] = 'b',
                PieceType.rook => str[4] = 'r',
                PieceType.queen => str[4] = 'q',
                else => unreachable,
            }
            return str;
        } else {
            var str = try allocator.alloc(u8, 4);
            std.mem.copy(u8, str[0..2], self.get_from().to_str());
            std.mem.copy(u8, str[2..4], self.get_to().to_str());
            return str;
        }
    }

    const MoveParseError = error{
        IllegalMove,
    };

    pub fn from_str(str: []const u8, allocator: Allocator, state: GameState) !Self {
        const from = Square.from_str(str[0..2]);
        const to = Square.from_str(str[2..4]);

        var move_list = ArrayList(Move).init(allocator);
        defer move_list.deinit();

        switch (state.active_color) {
            Color.white => try generate_moves(Color.white, state, &move_list),
            Color.black => try generate_moves(Color.black, state, &move_list),
        }
        for (move_list.items) |move| {
            const move_name = try move.to_str(allocator);
            allocator.free(move_name);
            if (move.from == from and move.to == to) {
                return move;
            }
        }
        return MoveParseError.IllegalMove;
    }
};

// Information that cannot be recovered after making a move
pub const MoveUndoInfo = struct {
    en_passant: ?Square,
    castling_rights: CastlingRights,
    captured_piece: ?Piece,
};

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

    pub inline fn as_board(self: *const Square) Bitboard {
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

    pub inline fn up_left(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 9);
    }

    pub inline fn up_right(self: *const Square) Square {
        return @intToEnum(Square, @enumToInt(self.*) - 7);
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

pub const Position = struct {
    pieces: [64]Piece,
    piece_bitboards: [2][6]Bitboard,
    color_bitboards: [2]Bitboard,
    occupied: Bitboard,

    const Self = @This();

    // pub fn as_array(self: *const Self) [2][6]Bitboard {
    //     return [2][6]Bitboard{
    //         [6]Bitboard{ self.white_pawns, self.white_knights, self.white_bishops, self.white_rooks, self.white_queens, self.white_king },
    //         [6]Bitboard{ self.black_pawns, self.black_knights, self.black_bishops, self.black_rooks, self.black_queens, self.black_king },
    //     };
    // }

    pub fn empty() Self {
        return Self{
            .pieces = [1]Piece{Piece.no_piece} ** 64,
            .piece_bitboards = [1][6]Bitboard{[1]Bitboard{0} ** 6} ** 2,
            .color_bitboards = [1]Bitboard{0} ** 2,
            .occupied = 0,
        };
    }

    pub fn king_square(comptime color: Color) Square {
        switch (color) {
            Color.white => return Square.E1,
            Color.black => return Square.E8,
        }
    }

    pub fn kingside_rook_square(comptime color: Color) Square {
        switch (color) {
            Color.white => return Square.H1,
            Color.black => return Square.H8,
        }
    }

    pub fn queenside_rook_square(comptime color: Color) Square {
        switch (color) {
            Color.white => return Square.A1,
            Color.black => return Square.A8,
        }
    }

    /// Print the formatted position to the terminal.
    /// This assumes that the position is valid, i.e no two pieces occupy the same position
    pub fn print(self: *const Self, writer: anytype) !void {
        var i: u6 = 0;
        while (i < 8) : (i += 1) {
            std.debug.print("{d}  ", .{8 - i});
            var j: u6 = 0;
            while (j < 8) : (j += 1) {
                const mask = @intToEnum(Square, i * 8 + j).as_board();
                if (self.pawns(Color.white) & mask != 0) {
                    _ = try writer.write("P");
                } else if (self.knights(Color.white) & mask != 0) {
                    _ = try writer.write("N");
                } else if (self.bishops(Color.white) & mask != 0) {
                    _ = try writer.write("B");
                } else if (self.rooks(Color.white) & mask != 0) {
                    _ = try writer.write("R");
                } else if (self.queens(Color.white) & mask != 0) {
                    _ = try writer.write("Q");
                } else if (self.king(Color.white) & mask != 0) {
                    _ = try writer.write("K");
                } else if (self.pawns(Color.black) & mask != 0) {
                    _ = try writer.write("p");
                } else if (self.knights(Color.black) & mask != 0) {
                    _ = try writer.write("n");
                } else if (self.bishops(Color.black) & mask != 0) {
                    _ = try writer.write("b");
                } else if (self.rooks(Color.black) & mask != 0) {
                    _ = try writer.write("r");
                } else if (self.queens(Color.black) & mask != 0) {
                    _ = try writer.write("q");
                } else if (self.king(Color.black) & mask != 0) {
                    _ = try writer.write("k");
                } else {
                    _ = try writer.write(".");
                }
                _ = try writer.write(" ");
            }
            _ = try writer.write("\n");
        }
        _ = try writer.write("\n   a b c d e f g h\n");
    }

    pub fn pawns(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.pawn)];
    }

    pub fn knights(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.knight)];
    }

    pub fn bishops(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.bishop)];
    }

    pub fn rooks(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.rook)];
    }

    pub fn queens(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.queen)];
    }

    pub fn king(self: *const Self, comptime color: Color) Bitboard {
        return self.piece_bitboards[@enumToInt(color)][@enumToInt(PieceType.king)];
    }

    pub fn occupied_by(self: *const Self, comptime color: Color) Bitboard {
        return self.color_bitboards[@enumToInt(color)];
    }

    pub fn place_piece(self: *Self, piece: Piece, square: Square) void {
        std.debug.assert(self.piece_at(square) == Piece.no_piece);

        const square_index = @enumToInt(square);
        const type_index = @enumToInt(piece.piece_type());
        const color_index = @enumToInt(piece.color());

        self.pieces[square_index] = piece;
        self.piece_bitboards[color_index][type_index] |= square.as_board();
        self.color_bitboards[color_index] |= square.as_board();
        self.occupied |= square.as_board();
    }

    pub fn remove_piece(self: *Self, square: Square) Piece {
        const piece = self.piece_at(square);
        std.debug.assert(piece != Piece.no_piece);

        const square_index = @enumToInt(square);
        const type_index = @enumToInt(piece.piece_type());
        const color_index = @enumToInt(piece.color());

        self.pieces[square_index] = Piece.no_piece;
        self.piece_bitboards[color_index][type_index] ^= square.as_board();
        self.color_bitboards[color_index] ^= square.as_board();
        self.occupied ^= square.as_board();
        return piece;
    }

    pub inline fn piece_at(self: *const Self, square: Square) Piece {
        return self.pieces[@enumToInt(square)];
    }

    /// Return a bitboard marking all the squares attacked(or guarded) by a piece of a certain color
    /// Note that the king is effectively considered to be nonexistent, as he cannot move
    /// to squares that are x-rayed by an opponent slider piece.
    /// So result is "a bitboard marking all positions that the opponent king cannot move to".
    pub fn king_unsafe_squares(self: *const Self, comptime us: Color) Bitboard {
        var attacked: Bitboard = 0;
        const them = comptime us.other();
        const all_without_king = self.occupied ^ self.king(us);

        // pawns
        const opponent_pawns = self.pawns(them);
        attacked |= bitboard.pawn_attacks(them, opponent_pawns);

        // knights
        attacked |= bitboard.knight_attacks(self.knights(them));

        // bishops
        var diag_sliders = self.bishops(them) | self.queens(them);
        while (diag_sliders != 0) : (bitops.pop_ls1b(&diag_sliders)) {
            const square = bitboard.get_lsb_square(diag_sliders);
            attacked |= bitboard.bishop_attacks(square, all_without_king);
        }

        // rooks
        var straight_sliders = self.rooks(them) | self.queens(them);
        while (straight_sliders != 0) : (bitops.pop_ls1b(&straight_sliders)) {
            const square = bitboard.get_lsb_square(straight_sliders);
            attacked |= bitboard.rook_attacks(square, all_without_king);
        }

        // king
        attacked |= bitboard.king_attacks(self.king(them));
        return attacked;
    }

    /// perform sanity checks for debugging
    fn is_ok(self: *const Self) bool {
        var squares = SquareIterator.new();
        if (self.occupied_by(Color.white) & self.occupied_by(Color.black) != 0 or self.occupied_by(Color.white) | self.occupied_by(Color.black) != self.occupied) {
            return false;
        }
        while (squares.next()) |square| {
            const index = @enumToInt(square);
            const pieces_on_that_field =
                ((self.pawns(Color.white) >> index) & 1) +
                ((self.pawns(Color.black) >> index) & 1) +
                ((self.knights(Color.white) >> index) & 1) +
                ((self.knights(Color.black) >> index) & 1) +
                ((self.bishops(Color.white) >> index) & 1) +
                ((self.bishops(Color.black) >> index) & 1) +
                ((self.rooks(Color.white) >> index) & 1) +
                ((self.rooks(Color.black) >> index) & 1) +
                ((self.queens(Color.white) >> index) & 1) +
                ((self.queens(Color.black) >> index) & 1) +
                ((self.king(Color.white) >> index) & 1) +
                ((self.king(Color.black) >> index) & 1);
            if (pieces_on_that_field > 1) {
                return false;
            }
        }
        return true;
    }
};

/// Iterator over all 64 squares on a chess board
pub const SquareIterator = struct {
    current_square: u7,

    const Self = @This();

    pub fn new() Self {
        return Self{
            .current_square = 0,
        };
    }

    pub fn next(self: *Self) ?Square {
        if (self.current_square == 64) {
            return null;
        } else {
            const square = @intToEnum(Square, self.current_square);
            self.current_square += 1;
            return square;
        }
    }
};

test "king unsafe squares" {
    const expectEqual = std.testing.expectEqual;

    const state = try GameState.from_fen("k6R/3r4/1p6/8/2n1K3/8/q7/3b4 w - - 0 1");
    try expectEqual(@as(Bitboard, 0xbfe3b4d9d0bf70b), state.position.king_unsafe_squares(Color.white));
}

test "update castling rights" {
    const expect = std.testing.expect;

    var state = try GameState.from_fen("r3k2r/3N4/8/8/p7/8/8/R3K2R w KQkq - 0 1");
    try expect(state.can_castle_kingside(Color.white));
    try expect(state.can_castle_queenside(Color.white));
    try expect(state.can_castle_kingside(Color.black));
    try expect(state.can_castle_queenside(Color.black));

    // moving the right rook voids kingside castling rights for white
    {
        const move = Move{
            .from = Square.H1,
            .to = Square.H4,
        };
        const undo_info = state.make_move(Color.white, move);

        try expect(!state.can_castle_kingside(Color.white));
        try expect(state.can_castle_queenside(Color.white));
        try expect(state.can_castle_kingside(Color.black));
        try expect(state.can_castle_queenside(Color.black));

        state.undo_move(move, undo_info);
    }

    // capturing with the left rook also voids castling rights
    {
        const move = Move{
            .from = Square.A1,
            .to = Square.A4,
        };
        const undo_info = state.make_move(Color.white, move);

        try expect(state.can_castle_kingside(Color.white));
        try expect(!state.can_castle_queenside(Color.white));
        try expect(state.can_castle_kingside(Color.black));
        try expect(state.can_castle_queenside(Color.black));

        state.undo_move(move, undo_info);
    }

    // moving the king voids castling rights on both sides
    {
        const move = Move{
            .from = Square.E1,
            .to = Square.E2,
        };
        const undo_info = state.make_move(Color.white, move);

        try expect(!state.can_castle_kingside(Color.white));
        try expect(!state.can_castle_queenside(Color.white));
        try expect(state.can_castle_kingside(Color.black));
        try expect(state.can_castle_queenside(Color.black));

        state.undo_move(move, undo_info);
    }

    // capturing (with the black king) does the same
    {
        const move = Move{
            .from = Square.E8,
            .to = Square.D7,
        };
        const undo_info = state.make_move(Color.black, move);

        try expect(state.can_castle_kingside(Color.white));
        try expect(state.can_castle_queenside(Color.white));
        try expect(!state.can_castle_kingside(Color.black));
        try expect(!state.can_castle_queenside(Color.black));

        state.undo_move(move, undo_info);
    }
}

test "en passant" {
    const expectEqual = std.testing.expectEqual;

    var state = try GameState.from_fen("k7/5p2/K7/8/5Pp1/8/8/8 w - f3 0 1");
    try expectEqual(Square.F3, state.en_passant.?);

    // next move resets en passant square
    {
        const move = Move{
            .from = Square.G4,
            .to = Square.G3,
        };
        const undo_info = state.make_move(Color.black, move);

        try expectEqual(null, state.en_passant);

        state.undo_move(move, undo_info);
    }

    // next move might also create a new en passant square
    {
        const move = Move{ .from = Square.F7, .to = Square.F5 };
        const undo_info = state.make_move(Color.black, move);
        try expectEqual(Square.F6, state.en_passant.?);

        state.undo_move(move, undo_info);
    }

    // assure post-en passant positions are correct
    // next move might also create a new en passant square
    {
        const move = Move{
            .from = Square.G4,
            .to = Square.F3,
        };
        const undo_info = state.make_move(Color.black, move);

        try expectEqual(@as(Bitboard, 0x200000002000), state.position.pawns(Color.black));
        try expectEqual(@as(Bitboard, 0), state.position.pawns(Color.white));

        state.undo_move(move, undo_info);
    }
}
