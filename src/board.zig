//! Defines the state of a chess board including a FEN parser 
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;
const bitops = @import("bitops.zig");

const zobrist = @import("zobrist.zig");

const generate_moves = @import("movegen.zig").generate_moves;

pub const MoveTag = enum(u3) {
    castle,
    double_push,
    promote,
    en_passant,
    capture,
    quiet,
};

pub const MoveType = union(MoveTag) {
    castle: CastleSwaps,
    double_push: void,
    en_passant: void,
    promote: PieceType,
    capture: PieceType,
    quiet: PieceType,
};

const FenParseResult = struct {
    active_color: Color,
    state: GameState,
};

pub fn parse_fen(fen: []const u8) !FenParseResult {
    var parts = std.mem.split(u8, fen, " ");
    const fen_position = parts.next().?;

    // parse position
    var pieces = [1]Bitboard{0} ** 12;
    var ranks = std.mem.split(u8, fen_position, "/");
    var rank: u6 = 0;
    while (ranks.next()) |entry| {
        var file: u6 = 0;
        for (entry) |c| {
            const square = @intToEnum(Square, rank * 8 + file);
            const piece_index: u4 = switch (c) {
                'P' => 0,
                'N' => 1,
                'B' => 2,
                'R' => 3,
                'Q' => 4,
                'K' => 5,
                'p' => 6,
                'n' => 7,
                'b' => 8,
                'r' => 9,
                'q' => 10,
                'k' => 11,
                '1'...'8' => {
                    file += @intCast(u4, c - '0');
                    continue;
                },
                else => {
                    return FenParseError.InvalidPosition;
                },
            };
            pieces[piece_index] ^= square.as_board();
            file += 1;
        }
        if (file != 8) return FenParseError.InvalidPosition;
        rank += 1;
    }
    if (rank != 8) return FenParseError.InvalidPosition;
    const position = Position.new(pieces[0], pieces[1], pieces[2], pieces[3], pieces[4], pieces[5], pieces[6], pieces[7], pieces[8], pieces[9], pieces[10], pieces[11]);

    // parse rights
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
    var en_passant_square: ?Square = null;
    if (!std.mem.eql(u8, en_passant_fen, "-")) {
        en_passant_square = Square.from_str(en_passant_fen);
    }
    const board_rights = BoardRights {
        .en_passant = en_passant_square,
        .white_kingside = white_kingside,
        .white_queenside = white_queenside,
        .black_kingside = black_kingside,
        .black_queenside = black_queenside,
    };

    return FenParseResult {
        .active_color = active_color,
        .state = GameState {
            .position = position,
            .board_rights = board_rights,
        },
    };
}

pub const Move = struct {
    from: Bitboard,
    to: Bitboard,
    move_type: MoveType,

    const Self = @This();

    /// Caller owns returned memory
    pub fn to_str(self: Self, allocator: Allocator) ![]const u8 {
        // Promotions need 5 bytes
        switch (self.move_type) {
            MoveType.promote => |promote_to| {
                var str = try allocator.alloc(u8, 5);
                std.mem.copy(u8, str[0..2], bitboard.get_lsb_square(self.from).to_str());
                std.mem.copy(u8, str[2..4], bitboard.get_lsb_square(self.to).to_str());
                switch (promote_to) {
                    PieceType.knight => str[4] = 'n',
                    PieceType.bishop => str[4] = 'b',
                    PieceType.rook => str[4] = 'r',
                    PieceType.queen => str[4] = 'q',
                    else => unreachable,
                }
                return str;
            },
            else => {
                var str = try allocator.alloc(u8, 4);
                std.mem.copy(u8, str[0..2], bitboard.get_lsb_square(self.from).to_str());
                std.mem.copy(u8, str[2..4], bitboard.get_lsb_square(self.to).to_str());
                return str;
            },
        }
    }

    const MoveParseError = error{
        IllegalMove,
    };

    pub fn from_str(str: []const u8, allocator: Allocator, active_color: Color, state: GameState) !Self {
        const from = Square.from_str(str[0..2]);
        const to = Square.from_str(str[2..4]);

        var move_list = ArrayList(Move).init(allocator);
        defer move_list.deinit();

        switch (active_color) {
            Color.white => try generate_moves(Color.white, state, &move_list),
            Color.black => try generate_moves(Color.black, state, &move_list),
        }
        for (move_list.items) |move| {
            const move_name = try move.to_str(allocator);
            allocator.free(move_name);
            if (bitboard.get_lsb_square(move.from) == from and
                bitboard.get_lsb_square(move.to) == to)
            {
                return move;
            }
        }
        return MoveParseError.IllegalMove;
    }
};

pub const WHITE_QUEENSIDE = CastleSwaps{
    .king = 0x1400000000000000,
    .rook = 0x900000000000000,
};

pub const WHITE_KINGSIDE = CastleSwaps{
    .king = 0x5000000000000000,
    .rook = 0xa000000000000000,
};

pub const BLACK_KINGSIDE = CastleSwaps{
    .king = 0x50,
    .rook = 0xa0,
};

pub const BLACK_QUEENSIDE = CastleSwaps{
    .king = 0x14,
    .rook = 0x9,
};

pub const CastleDirection = enum(u1) {
    kingside,
    queenside,
};

const CastleSwaps = struct {
    king: Bitboard,
    rook: Bitboard,
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

pub const GameState = struct {
    position: Position,
    board_rights: BoardRights,

    const Self = @This();

    pub fn can_castle_kingside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.board_rights.white_kingside,
            Color.black => return self.board_rights.black_kingside,
        }
    }

    pub fn can_castle_queenside(self: *const Self, comptime color: Color) bool {
        switch (color) {
            Color.white => return self.board_rights.white_queenside,
            Color.black => return self.board_rights.black_queenside,
        }
    }

    pub fn make_move(self: *const Self, comptime color: Color, move: Move) Self {
        return Self {
            .position = self.position.make_move(color, move),
            .board_rights = self.board_rights.make_move(color, move),
        };
    }

    pub fn initial() Self {
        return Self {
            .position = Position.starting_position(),
            .board_rights = BoardRights.initial(),
        };
    }

    pub fn print(self: *const Self) !void {
        const stdout = std.io.getStdOut().writer();
        try self.position.print(stdout);
        try self.board_rights.print(stdout);
    }
};

pub const BoardRights = struct {
    /// whether or not en passant is currently possible (rare)
    en_passant: ?Square,
    /// Whether or not white can castle kingside
    white_kingside: bool,
    /// Whether or not white can castle queenside
    white_queenside: bool,
    /// Whether or not black can castle kingside
    black_kingside: bool,
    /// Whether or not black can castle queenside
    black_queenside: bool,

    const Self = @This();

    pub fn new(ep: ?Square, wk: bool, wq: bool, bk: bool, bq: bool) Self {
        return Self{
            .en_passant = ep,
            .white_kingside = wk,
            .white_queenside = wq,
            .black_kingside = bk,
            .black_queenside = bq,
        };
    }

    pub fn initial() Self {
        return Self.new(null, true, true, true, true);
    }

    pub fn make_move(self: *const Self, comptime color: Color, move: Move) Self {
        var en_passant: ?Square = null; // resets after each move by default
        var white_kingside = self.white_kingside;
        var white_queenside = self.white_queenside;
        var black_kingside = self.black_kingside;
        var black_queenside = self.black_queenside;

        switch (move.move_type) {
            MoveType.double_push => {
                // Update en passant rights
                const to = bitboard.get_lsb_square(move.to);
                switch (color) {
                    Color.white => en_passant = to.down_one(),
                    Color.black => en_passant = to.up_one(),
                }
            },
            MoveType.quiet => |piece_type| {
                if (piece_type == PieceType.king) {
                    switch (color) {
                        Color.white => {
                            white_kingside = false;
                            white_queenside = false;
                        },
                        Color.black => {
                            black_kingside = false;
                            black_queenside = false;
                        },
                    }
                }
            },
            MoveType.castle => |_| {
                switch (color) {
                    Color.white => {
                        white_kingside = false;
                        white_queenside = false;
                    },
                    Color.black => {
                        black_kingside = false;
                        black_queenside = false;
                    },
                }
            },
            MoveType.capture => |piece_type| {
                if (piece_type == PieceType.king) {
                    switch (color) {
                        Color.white => {
                            white_kingside = false;
                            white_queenside = false;
                        },
                        Color.black => {
                            black_kingside = false;
                            black_queenside = false;
                        },
                    }
                }
            },
            else => {},
        }

        if (move.from == Square.A1.as_board()) {
            white_queenside = false;
        } else if (move.from == Square.A8.as_board()) {
            black_queenside = false;
        } else if (move.from == Square.H1.as_board()) {
            white_kingside = false;
        } else if (move.from == Square.H8.as_board()) {
            black_kingside = false;
        }

        return Self {
            .en_passant = en_passant,
            .white_kingside = white_kingside,
            .white_queenside = white_queenside,
            .black_kingside = black_kingside,
            .black_queenside = black_queenside,
        };
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

        if (self.en_passant) |square| {
            _ = try std.fmt.format(writer, "En passant Square: {s}\n", .{SQUARE_NAME[@enumToInt(square)]});
        } else {
            _ = try writer.write("No en passant possible\n");
        }
    }
};


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

pub const Position = struct {
    white_pawns: Bitboard,
    white_knights: Bitboard,
    white_bishops: Bitboard,
    white_rooks: Bitboard,
    white_queens: Bitboard,
    white_king: Bitboard,
    black_pawns: Bitboard,
    black_knights: Bitboard,
    black_bishops: Bitboard,
    black_rooks: Bitboard,
    black_queens: Bitboard,
    black_king: Bitboard,
    black: Bitboard,
    white: Bitboard,
    occupied: Bitboard,

    const Self = @This();

    fn new(white_pawns: Bitboard, white_knights: Bitboard, white_bishops: Bitboard, white_rooks: Bitboard, white_queens: Bitboard, white_king: Bitboard, black_pawns: Bitboard, black_knights: Bitboard, black_bishops: Bitboard, black_rooks: Bitboard, black_queens: Bitboard, black_king: Bitboard) Self {
        const white = white_pawns | white_knights | white_bishops | white_rooks | white_queens | white_king;
        const black = black_pawns | black_knights | black_bishops | black_rooks | black_queens | black_king;
        return Self{
            .white_pawns = white_pawns,
            .white_knights = white_knights,
            .white_bishops = white_bishops,
            .white_rooks = white_rooks,
            .white_queens = white_queens,
            .white_king = white_king,
            .black_pawns = black_pawns,
            .black_knights = black_knights,
            .black_bishops = black_bishops,
            .black_rooks = black_rooks,
            .black_queens = black_queens,
            .black_king = black_king,
            .white = white,
            .black = black,
            .occupied = white | black,
        };
    }


    pub fn as_array(self: *const Self) [2][6]Bitboard {
        return [2][6]Bitboard {
            [6]Bitboard { self.white_pawns, self.white_knights, self.white_bishops, self.white_rooks, self.white_queens, self.white_king },
            [6]Bitboard { self.black_pawns, self.black_knights, self.black_bishops, self.black_rooks, self.black_queens, self.black_king },
        };
    }

    /// Create a new board with the starting position
    pub fn starting_position() Self {
        return Self {
            .white_pawns = 0xff000000000000,
            .white_knights = 0x4200000000000000,
            .white_bishops = 0x2400000000000000,
            .white_rooks = 0x8100000000000000,
            .white_queens = 0x800000000000000,
            .white_king = 0x1000000000000000,
            .black_pawns = 0xff00,
            .black_knights = 0x42,
            .black_bishops = 0x24,
            .black_rooks = 0x81,
            .black_queens = 0x8,
            .black_king = 0x10,
            .white = 0xffff000000000000,
            .black = 0xffff,
            .occupied = 0xffff00000000ffff,

        };
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

                if (self.white_pawns & mask != 0) {
                    _ = try writer.write("P");
                } else if (self.white_knights & mask != 0) {
                    _ = try writer.write("N");
                } else if (self.white_bishops & mask != 0) {
                    _ = try writer.write("B");
                } else if (self.white_rooks & mask != 0) {
                    _ = try writer.write("R");
                } else if (self.white_queens & mask != 0) {
                    _ = try writer.write("Q");
                } else if (self.white_king & mask != 0) {
                    _ = try writer.write("K");
                } else if (self.black_pawns & mask != 0) {
                    _ = try writer.write("p");
                } else if (self.black_knights & mask != 0) {
                    _ = try writer.write("n");
                } else if (self.black_bishops & mask != 0) {
                    _ = try writer.write("b");
                } else if (self.black_rooks & mask != 0) {
                    _ = try writer.write("r");
                } else if (self.black_queens & mask != 0) {
                    _ = try writer.write("q");
                } else if (self.black_king & mask != 0) {
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
        switch (color) {
            Color.white => return self.white_pawns,
            Color.black => return self.black_pawns,
        }
    }

    pub fn knights(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_knights,
            Color.black => return self.black_knights,
        }
    }

    pub fn bishops(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_bishops,
            Color.black => return self.black_bishops,
        }
    }

    pub fn rooks(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_rooks,
            Color.black => return self.black_rooks,
        }
    }

    pub fn queens(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_queens,
            Color.black => return self.black_queens,
        }
    }

    pub fn king(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white_king,
            Color.black => return self.black_king,
        }
    }

    pub fn occupied_by(self: *const Self, comptime color: Color) Bitboard {
        switch (color) {
            Color.white => return self.white,
            Color.black => return self.black,
        }
    }

    pub fn make_move(self: *const Self, comptime color: Color, move: Move) Position {
        std.debug.assert(self.is_ok());
        const wp = self.white_pawns;
        const wn = self.white_knights;
        const wb = self.white_bishops;
        const wr = self.white_rooks;
        const wq = self.white_queens;
        const wk = self.white_king;
        const bp = self.black_pawns;
        const bn = self.black_knights;
        const bb = self.black_bishops;
        const br = self.black_rooks;
        const bq = self.black_queens;
        const bk = self.black_king;

        const from = move.from;
        const to = move.to;

        switch (color) {
            Color.white => {
                switch (move.move_type) {
                    MoveTag.castle => |swaps| {
                        return Self.new(wp, wn, wb, wr ^ swaps.rook, wq, wk ^ swaps.king, bp, bn, bb, br, bq, bk);
                    },
                    MoveTag.double_push => {
                        return Self.new(wp ^ (from | to), wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk);
                    },
                    MoveTag.promote => |promote_to| {
                        const r = ~to;
                        switch (promote_to) {
                            // zig fmt: off
                            PieceType.queen  => return Self.new(wp ^ from, wn, wb, wr, wq ^ to, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.rook   => return Self.new(wp ^ from, wn, wb, wr ^ to, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.bishop => return Self.new(wp ^ from, wn, wb ^ to, wr, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.knight => return Self.new(wp ^ from, wn ^ to, wb, wr, wq, wk, bp, bn & r, bb & r, br & r, bq & r, bk),
                            else => unreachable,
                            // zig fmt: on
                        }
                    },
                    MoveTag.en_passant => {
                        const r = ~bitboard.get_lsb_square(to).down_one().as_board();
                        const m = (from | to);
                        return Self.new(wp ^ m, wn, wb, wr, wq, wk, bp & r, bn, bb, br, bq, bk);
                    },
                    MoveTag.capture => |piece_type| {
                        const r = ~to;
                        std.debug.assert(move.to & self.white == 0);
                        std.debug.assert(to & bk == 0);
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp ^ m, wn, wb, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.knight => return Self.new(wp, wn ^ m, wb, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb ^ m, wr, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr ^ m, wq, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq ^ m, wk, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk ^ m, bp & r, bn & r, bb & r, br & r, bq & r, bk),
                            // zig fmt: on
                        }
                    },
                    MoveTag.quiet => |piece_type| {
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp ^ m, wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp, wn ^ m, wb, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb ^ m, wr, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr ^ m, wq, wk, bp, bn, bb, br, bq, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq ^ m, wk, bp, bn, bb, br, bq, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk ^ m, bp, bn, bb, br, bq, bk),
                            // zig fmt: on
                        }
                    },
                }
            },
            Color.black => {
                switch (move.move_type) {
                    MoveTag.castle => |swaps| {
                        return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br ^ swaps.rook, bq, bk ^ swaps.king);
                    },
                    MoveTag.double_push => {
                        return Self.new(wp, wn, wb, wr, wq, wk, bp ^ (from | to), bn, bb, br, bq, bk);
                    },
                    MoveTag.promote => |promote_to| {
                        const r = ~to;
                        switch (promote_to) {
                            // zig fmt: off
                            PieceType.queen  => return Self.new(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb, br, bq ^ to, bk),
                            PieceType.rook   => return Self.new(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb, br ^ to, bq, bk),
                            PieceType.bishop => return Self.new(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn, bb ^ to, br, bq, bk),
                            PieceType.knight => return Self.new(wp, wn & r, wb & r, wr & r, wq & r, wk, bp ^ from, bn ^ to, bb, br, bq, bk),
                            else => unreachable,
                            // zig fmt: on
                        }
                    },
                    MoveTag.en_passant => {
                        const r = ~bitboard.get_lsb_square(to).up_one().as_board();
                        const m = (from | to);
                        return Self.new(wp & r, wn, wb, wr, wq, wk, bp ^ m, bn, bb, br, bq, bk);
                    },
                    MoveTag.capture => |piece_type| {
                        const r = ~to;
                        std.debug.assert(move.to & self.black == 0);
                        std.debug.assert(to & wk == 0);
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp ^ m, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp, bn ^ m, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp, bn, bb ^ m, br, bq, bk),
                            PieceType.rook   => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp, bn, bb, br ^ m, bq, bk),
                            PieceType.queen  => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp, bn, bb, br, bq ^ m, bk),
                            PieceType.king   => return Self.new(wp & r, wn & r, wb & r, wr & r, wq & r, wk, bp, bn, bb, br, bq, bk ^ m),
                            // zig fmt: on
                        }
                    },
                    MoveTag.quiet => |piece_type| {
                        const m = (from | to);
                        switch (piece_type) {
                            // zig fmt: off
                            PieceType.pawn   => return Self.new(wp, wn, wb, wr, wq, wk, bp ^ m, bn, bb, br, bq, bk),
                            PieceType.knight => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn ^ m, bb, br, bq, bk),
                            PieceType.bishop => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb ^ m, br, bq, bk),
                            PieceType.rook   => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br ^ m, bq, bk),
                            PieceType.queen  => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br, bq ^ m, bk),
                            PieceType.king   => return Self.new(wp, wn, wb, wr, wq, wk, bp, bn, bb, br, bq, bk ^ m),
                            // zig fmt: on
                        }
                    },
                }
            },
        }
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
        if (self.white & self.black != 0 or self.black | self.white != self.occupied) {
            std.debug.print("occupancy error\n", .{});
            return false;
        }
        while (squares.next()) |square| {
            const index = @enumToInt(square);
            const pieces_on_that_field = 
                ((self.white_pawns >> index) & 1) + 
                ((self.white_knights >> index) & 1) + 
                ((self.white_bishops >> index) & 1) + 
                ((self.white_rooks >> index) & 1) + 
                ((self.white_queens >> index) & 1) + 
                ((self.white_king >> index) & 1) + 
                ((self.black_pawns >> index) & 1) + 
                ((self.black_knights >> index) & 1) + 
                ((self.black_bishops >> index) & 1) + 
                ((self.black_rooks >> index) & 1) + 
                ((self.black_queens >> index) & 1) + 
                ((self.black_king >> index) & 1);
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
        return Self {
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

    const state = (try parse_fen("k6R/3r4/1p6/8/2n1K3/8/q7/3b4 w - - 0 1")).state;
    try expectEqual(@as(Bitboard, 0xbfe3b4d9d0bf70b), state.position.king_unsafe_squares(Color.white));
}

test "update castling rights" {
    const expect = std.testing.expect;
    var new_state: GameState = undefined;

    const state = (try parse_fen("r3k2r/3N4/8/8/p7/8/8/R3K2R w KQkq - 0 1")).state;
    try expect(state.can_castle_kingside(Color.white));
    try expect(state.can_castle_queenside(Color.white));
    try expect(state.can_castle_kingside(Color.black));
    try expect(state.can_castle_queenside(Color.black));

    // moving the right rook voids kingside castling rights for white
    new_state = state.make_move(Color.white, Move {
        .from = Square.H1.as_board(),
        .to = Square.H2.as_board(),
        .move_type = MoveType{ .quiet = PieceType.rook },
    });
    try expect(!new_state.can_castle_kingside(Color.white));
    try expect(new_state.can_castle_queenside(Color.white));
    try expect(new_state.can_castle_kingside(Color.black));
    try expect(new_state.can_castle_queenside(Color.black));

    // capturing with the left rook also voids castling rights
    new_state = state.make_move(Color.white, Move {
        .from = Square.A1.as_board(),
        .to = Square.A4.as_board(),
        .move_type = MoveType{ .capture = PieceType.rook },
    });
    try expect(new_state.can_castle_kingside(Color.white));
    try expect(!new_state.can_castle_queenside(Color.white));
    try expect(new_state.can_castle_kingside(Color.black));
    try expect(new_state.can_castle_queenside(Color.black));

    // moving the king voids castling rights on both sides
    new_state = state.make_move(Color.white, Move {
        .from = Square.E1.as_board(),
        .to = Square.E2.as_board(),
        .move_type = MoveType{ .quiet = PieceType.king },
    });
    try expect(!new_state.can_castle_kingside(Color.white));
    try expect(!new_state.can_castle_queenside(Color.white));
    try expect(new_state.can_castle_kingside(Color.black));
    try expect(new_state.can_castle_queenside(Color.black));

    // capturing (with the black king) does the same
    new_state = state.make_move(Color.black, Move {
        .from = Square.E8.as_board(),
        .to = Square.D7.as_board(),
        .move_type = MoveType{ .capture = PieceType.king },
    });
    try expect(new_state.can_castle_kingside(Color.white));
    try expect(new_state.can_castle_queenside(Color.white));
    try expect(!new_state.can_castle_kingside(Color.black));
    try expect(!new_state.can_castle_queenside(Color.black));

}

test "en passant" {
    const expectEqual = std.testing.expectEqual;
    var new_state: GameState = undefined;

    const state = (try parse_fen("k7/5p2/K7/8/5Pp1/8/8/8 w - f3 0 1")).state;
    try expectEqual(Square.F3, state.board_rights.en_passant.?);

    // next move resets en passant square
    new_state = state.make_move(Color.black, Move {
        .from = Square.G4.as_board(),
        .to = Square.G3.as_board(),
        .move_type = MoveType { .quiet = PieceType.pawn },
    });
    try expectEqual(null, new_state.board_rights.en_passant);

    // next move might also create a new en passant square
    new_state = state.make_move(Color.black, Move {
        .from = Square.F7.as_board(),
        .to = Square.F5.as_board(),
        .move_type = MoveType.double_push,
    });
    try expectEqual(Square.F6, new_state.board_rights.en_passant.?);

    // assure post-en passant positions are correct
    // next move might also create a new en passant square
    new_state = state.make_move(Color.black, Move {
        .from = Square.G4.as_board(),
        .to = Square.F3.as_board(),
        .move_type = MoveType.en_passant,
    });
    try expectEqual(@as(Bitboard, 0x200000002000), new_state.position.pawns(Color.black));
    try expectEqual(@as(Bitboard, 0), new_state.position.pawns(Color.white));
}
