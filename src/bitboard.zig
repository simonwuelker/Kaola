//! Contains regular and magic bitboards 
//! as well as attack generation code

const std = @import("std");
const bitops = @import("bitops.zig");
const board_module = @import("board.zig");
const Square = board_module.Square;
const Color = board_module.Color;
const rand = @import("rand.zig");

const has_pext = bitops.has_pext;
const pext = bitops.pext;

pub const RANK_1: Bitboard = 0xff00000000000000;
pub const RANK_2: Bitboard = 0x00ff000000000000;
pub const RANK_3: Bitboard = 0x0000ff0000000000;
pub const RANK_4: Bitboard = 0x000000ff00000000;
pub const RANK_5: Bitboard = 0x00000000ff000000;
pub const RANK_6: Bitboard = 0x0000000000ff0000;
pub const RANK_7: Bitboard = 0x000000000000ff00;
pub const RANK_8: Bitboard = 0x00000000000000ff;

pub const FILE_A: Bitboard = 0x0101010101010101;
pub const FILE_B: Bitboard = 0x0202020202020202;
pub const FILE_C: Bitboard = 0x0404040404040404;
pub const FILE_D: Bitboard = 0x0808080808080808;
pub const FILE_E: Bitboard = 0x1010101010101010;
pub const FILE_F: Bitboard = 0x2020202020202020;
pub const FILE_G: Bitboard = 0x4040404040404040;
pub const FILE_H: Bitboard = 0x8080808080808080;

pub const Bitboard = u64;

const BISHOP_RELEVANT_BITS = [64]u6{
    // zig fmt: off
    6, 5, 5, 5, 5, 5, 5, 6,
    5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 7, 7, 7, 7, 5, 5,
    5, 5, 7, 9, 9, 7, 5, 5,
    5, 5, 7, 9, 9, 7, 5, 5,
    5, 5, 7, 7, 7, 7, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5,
    6, 5, 5, 5, 5, 5, 5, 6,
    // zig fmt: on
};

const ROOK_RELEVANT_BITS = [64]u6{
    // zig fmt: off
    12, 11, 11, 11, 11, 11, 11, 12,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    12, 11, 11, 11, 11, 11, 11, 12,
    // zig fmt: on
};

pub const Magic = struct {
    attacks: []Bitboard,
    mask: Bitboard,
    shift: u6, 
    magic: u64,

    const Self = @This();

    pub fn index(self: *const Self, occupied: Bitboard) u64 {
        if( comptime has_pext()) {
            return pext(occupied, self.mask);
        } else {
            return ((occupied & self.mask) *% self.magic) >> self.shift;
        }
    }
};

var rook_table: [0x19000]Bitboard = undefined;
var bishop_table: [0x1480]Bitboard = undefined;

var rook_magics: [64]Magic = undefined;
pub var bishop_magics: [64]Magic = undefined;

pub const Slider = enum {
    Straight,
    Diagonal,
};

inline fn relevant_bits(comptime slider: Slider, square: Square) u6 {
    const index = @enumToInt(square);
    switch (slider) {
        Slider.Straight => return ROOK_RELEVANT_BITS[index],
        Slider.Diagonal => return BISHOP_RELEVANT_BITS[index],
    }
}

inline fn magics(comptime slider: Slider, square: Square) *Magic {
    const index = @enumToInt(square);
    switch (slider) {
        Slider.Straight => return &rook_magics[index],
        Slider.Diagonal => return &bishop_magics[index],
    }
}

fn attack_table(comptime slider: Slider) []Bitboard {
    switch (slider) {
        Slider.Straight => return rook_table[0..rook_table.len],
        Slider.Diagonal => return bishop_table[0..bishop_table.len],
    }
}

inline fn mask_rank(square: Square) Bitboard {
    return RANK_8 << (8 * @intCast(u6, square.rank()));
}

inline fn mask_file(square: Square) Bitboard {
    return FILE_A << square.file();
}

fn attacks_in_direction(start: Square, signed_shift: i5, blocked: Bitboard) Bitboard {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var square = @enumToInt(start);
    var attack_mask: Bitboard = 0;
    var i: u3 = 0;
    while (i < max_moves and (blocked >> square) & 1 == 0) : (i += 1) {
        if (negative_shift) square -= shift else square += shift;
        attack_mask |= @as(Bitboard, 1) << square;
    }
    return attack_mask;
}

fn generate_slider_attacks(comptime slider: Slider, square: Square, blocked: Bitboard) Bitboard {
    switch (slider) {
        Slider.Straight => {
            return attacks_in_direction(square, 8, blocked)
                | attacks_in_direction(square, -8, blocked)
                | attacks_in_direction(square, 1, blocked)
                | attacks_in_direction(square, -1, blocked);
        },
        Slider.Diagonal => {
            return attacks_in_direction(square, 7, blocked)
                | attacks_in_direction(square, -7, blocked)
                | attacks_in_direction(square, 9, blocked)
                | attacks_in_direction(square, -9, blocked);
        },
    }
}

pub fn init_magics() void {
    init_slider_magics(Slider.Straight);
    init_slider_magics(Slider.Diagonal);
}

fn init_slider_magics(comptime slider: Slider) void {
    var size: u64 = 0;

    var reference_attacks: [4096]Bitboard = undefined;
    var occupancies: [4096]Bitboard = undefined;

    // Utility array to prevent having to reset the hash buckets on every failed attempt.
    // (instead, we simply check if they were set in the current iteration and if not, overwrite them)
    var last_modified_at: [4096]u64 = [1]u64{0} ** 4096;
    var epoch: u64 = 0;

    var total_attack_size: u64 = 0;
    var squares = SquareIterator.new();
    while (squares.next()) |square| {
        // std.debug.print("{s}\n", .{@tagName(square)});
        const edges = ((RANK_1 | RANK_8) & ~mask_rank(square)) | ((FILE_A | FILE_H) & ~mask_file(square));

        var m = magics(slider, square);
        m.*.mask = generate_slider_attacks(slider, square, 0) & ~edges;
        m.*.shift = ~@as(u6, 0) - relevant_bits(slider, square) + 1;
        m.*.magic = 0;

        var blocked: Bitboard = 0;
        size = 0;
        // use carry-rippler trick to iterate through every possible blocking combination
        while(true) {
            occupancies[size] = blocked;
            reference_attacks[size] = generate_slider_attacks(slider, square, blocked);

            size += 1;
            blocked = (blocked -% m.mask) & m.mask;

            if (blocked == 0) break;
        }
        m.*.attacks = attack_table(slider)[total_attack_size..total_attack_size + size];
        total_attack_size += size;

        if (comptime has_pext()) {
            // pext hashing does not depend on magic numbers, so we only need to populate the attack table
            var i: u64 = 0;
            while (i < size) : (i += 1) {
                const hash = m.index(occupancies[i]);
                m.*.attacks[hash] =  reference_attacks[i];
            }
        } else {
            // find magic number the regular way
            var rng = rand.Rand64.new();
            search_magic: while (true) {
                // random number with a low number of set bits
                const magic: u64 = rng.next() & rng.next() & rng.next();

                // skip bad magic numbers
                if (@popCount((m.*.mask *% magic) >> 56) < 6) continue;
                m.*.magic = magic;

                epoch += 1;
                var i: u64 = 0;
                while (i < size) : (i += 1) {
                    const hash = m.index(occupancies[i]);

                    // we use m.attacks as an array of hash buckets.
                    // That way, if we find a good magic number, the attack table will already be filled

                    // The epoch number is "i + 1" instead of just "i" because i starts at zero and the last_modified
                    // value should be smaller but also unsigned - so we take a seperate counter that is i + 1 as the 
                    // epoch number
                    if (last_modified_at[hash] < epoch) {
                        // bucket unused
                        m.*.attacks[hash] = reference_attacks[i];
                        last_modified_at[hash] = epoch;
                    } else if (m.*.attacks[hash] != reference_attacks[i]) {
                        // hash collision with different attacks, bad magic value
                        // note that we do allow hash collisions as long as they produce the same attack pattern
                        continue :search_magic;
                    }
                }
                // if we haven't hit continue yet, then the magic is good
                break;
            }
        }
    }
}

pub fn print_bitboard(board: Bitboard, title: []const u8) void {
    std.debug.print("\n==> {s}(0x{x})\n", .{title, board});
    var i: u6 = 0;
    while (i < 8) : (i += 1) {
        std.debug.print("{d}  ", .{8 - i});
        var j: u6 = 0;
        while (j < 8) : (j += 1) {
            if (board >> (i * 8 + j) & 1 != 0) {
                std.debug.print("1 ", .{});
            } else {
                std.debug.print(". ", .{});
            }
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("\n   a b c d e f g h\n", .{});
}


fn bitboard_distance_to_edge(square: Square, shift: i5) u3 {
    return switch (shift) {
        1 => @as(u3, 7) - square.file(),
        -1 => square.file(),
        8 => @as(u3, 7) - square.rank(),
        -8 => square.rank(),
        9 => std.math.min(@as(u3, 7) - square.file(), @as(u6, 7) - square.rank()),
        -7 => std.math.min(@as(u3, 7) - square.file(), square.rank()),
        -9 => std.math.min(square.file(), square.rank()),
        7 => std.math.min(square.file(), @as(u3, 7) - square.rank()),
        else => unreachable,
    };
}

/// Get the index of the least significant bit in a bitboard.
/// Causes undefined behaviour if the bitboard has no bit set.
pub inline fn get_lsb_square(board: Bitboard) Square {
    std.debug.assert(board != 0);
    return @intToEnum(Square, @ctz(board));
}

/// Compute the left attacks for a set of pawns
/// (Left from white's POV)
pub inline fn pawn_attacks_left(comptime color: Color, board: Bitboard) Bitboard {
    if (color == Color.white) {
        return (board & ~FILE_A) >> 9;
    } else {
        return (board & ~FILE_A) << 7;
    }
}

/// Compute the right attacks for a set of pawns
/// (Left from white's POV)
pub inline fn pawn_attacks_right(comptime color: Color, board: Bitboard) Bitboard {
    if (color == Color.white) {
        return (board & ~FILE_H) >> 7;
    } else {
        return (board & ~FILE_H) << 9;
    }
}

pub inline fn pawn_attacks(comptime color: Color, board: Bitboard) Bitboard {
    return pawn_attacks_left(color, board) | pawn_attacks_right(color, board);
}

pub fn king_attacks(board: Bitboard) Bitboard {
    return ((board & ~FILE_A) >> 1) // left
    | ((board & ~FILE_H) << 1) // right
    | (board << 8) // down
    | (board >> 8) // up
    | ((board & ~FILE_A) >> 9) // up left
    | ((board & ~FILE_H) >> 7) // up right
    | ((board & ~FILE_H) << 9) // down right
    | ((board & ~FILE_A) << 7); // down left
}

pub fn knight_attack(square: Square) Bitboard {
    return knight_attacks(square.as_board());
}

/// Take a bitboard of knights and produce a bitboard marking their attacks
pub fn knight_attacks(board: Bitboard) Bitboard {
    return ((board & ~FILE_A) >> 17) // up up left
    | ((board & ~FILE_H) >> 15) // up up right
    | ((board & ~(FILE_G | FILE_H)) >> 6) // up right right
    | ((board & ~(FILE_G | FILE_H)) << 10) // down right right
    | ((board & ~FILE_H) << 17) // down down right
    | ((board & ~FILE_A) << 15) // down down left
    | ((board & ~(FILE_A | FILE_B)) << 6) // down left left
    | ((board & ~(FILE_A | FILE_B)) >> 10); // up left left
}

pub fn bishop_attacks(square: Square, blocked: Bitboard) Bitboard {
    const magic = bishop_magics[@enumToInt(square)];
    return magic.attacks[magic.index(blocked)];
}

pub fn rook_attacks(square: Square, blocked: Bitboard) Bitboard {
    const magic = rook_magics[@enumToInt(square)];
    return magic.attacks[magic.index(blocked)];
}

/// A lookup table containing the paths between any two squares on the board.
/// Source square is included, target square is not.
/// The table should be indexed like this: `PATH_BETWEEN_SQUARES[source][target]`.
/// Results is undefined if source == target
var PATH_BETWEEN_SQUARES: [64][64]Bitboard = undefined;

pub fn init_paths_between_squares() void {
    var source_index: u6 = 0;
    while (true) : (source_index += 1) {
        var target_index: u6 = 0;
        while (true) : (target_index += 1) {
            const source = @intToEnum(Square, source_index);
            const target = @intToEnum(Square, target_index);

            const blocked = source.as_board() | target.as_board();
            // if horizontally aligned
            if (source.rank() == target.rank() or source.file() == target.file()) {
                PATH_BETWEEN_SQUARES[source_index][target_index] = rook_attacks(source, blocked) & rook_attacks(target, blocked);
                PATH_BETWEEN_SQUARES[source_index][target_index] ^= source.as_board();
            }
            // if diagonally aligned (if the absolute difference between their ranks is the same as their files
            else if (@maximum(source.rank(), target.rank()) - @minimum(source.rank(), target.rank()) ==
                @maximum(source.file(), target.file()) - @minimum(source.file(), target.file()))
            {
                PATH_BETWEEN_SQUARES[source_index][target_index] = bishop_attacks(source, blocked) & bishop_attacks(target, blocked);
                PATH_BETWEEN_SQUARES[source_index][target_index] ^= source.as_board();
            } else {
                // no straight path => 0
                PATH_BETWEEN_SQUARES[source_index][target_index] = 0;
            }
            if (target_index == 63) break;
        }

        if (source_index == 63) break;
    }
}

pub inline fn path_between_squares(from: Square, to: Square) Bitboard {
    return PATH_BETWEEN_SQUARES[@enumToInt(from)][@enumToInt(to)];
}

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

test "rook attacks" {
    const expectEqual = std.testing.expectEqual;

    // D4, C4, D1, D7 and G6 blocked
    const blocked = 0x800000c00400800;
    try expectEqual(rook_attacks(Square.D4, blocked), 0x80808f408080800);

    try expectEqual(rook_attacks(Square.A1, 0 ^ @enumToInt(Square.A1)), 0xfe01010101010101);
}

test "bishop attacks" {
    const expectEqual = std.testing.expectEqual;

    // D4, C5, F6, G1 and G3 blocked
    const blocked = 0x4000400804200000;
    try expectEqual(bishop_attacks(Square.D4, blocked), 0x4122140014200000);

    try expectEqual(bishop_attacks(Square.A1, 0 ^ @enumToInt(Square.A1)), 0x2040810204080);
}

test "knight attacks" {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(knight_attack(Square.D4), 0x14220022140000);
    try expectEqual(knight_attack(Square.A1), 0x4020000000000);
}

test "king attacks" {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(king_attacks(Square.D4.as_board()), 0x1c141c000000);
    try expectEqual(king_attacks(Square.A1.as_board()), 0x203000000000000);
}

test "white pawn attacks" {
    const expectEqual = std.testing.expectEqual;

    // pawns on A3, D5 and H5
    try expectEqual(pawn_attacks(Color.white, 0x10088000000), 0x200540000);

}

test "black pawn attacks" {
    const expectEqual = std.testing.expectEqual;

    // pawns on A3, D5 and H5
    try expectEqual(pawn_attacks(Color.black, 0x10088000000), 0x2005400000000);
}
