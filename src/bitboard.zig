//! Contains regular and magic bitboards 
//! as well as attack generation code

const std = @import("std");
const bitops = @import("bitops.zig");
const board_module = @import("board.zig");
const Square = board_module.Square;
const Color = board_module.Color;
const rand = @import("rand.zig");
// const magics = @import("magics.zig");

pub const RANK_1 = 0xff00000000000000;
pub const RANK_2 = 0x00ff000000000000;
pub const RANK_3 = 0x0000ff0000000000;
pub const RANK_4 = 0x000000ff00000000;
pub const RANK_5 = 0x00000000ff000000;
pub const RANK_6 = 0x0000000000ff0000;
pub const RANK_7 = 0x000000000000ff00;
pub const RANK_8 = 0x00000000000000ff;

pub const FILE_A = 0x0101010101010101;
pub const FILE_B = 0x0202020202020202;
pub const FILE_C = 0x0404040404040404;
pub const FILE_D = 0x0808080808080808;
pub const FILE_E = 0x1010101010101010;
pub const FILE_F = 0x2020202020202020;
pub const FILE_G = 0x4040404040404040;
pub const FILE_H = 0x8080808080808080;

pub const Bitboard = u64;

pub const Magic = struct {
    ptr: []Bitboard,
    mask: Bitboard,
    shift: u6, 
    magic: u64,

    const Self = @This();

    pub fn index(self: *const Self, occupied: Bitboard) u64 {
        return ((occupied & self.mask) *% self.magic) >> self.shift;
    }
};

var rook_table: [0x19000]Bitboard = undefined;
var bishop_table: [0x1480]Bitboard = undefined;


pub var rook_magics: [64]Magic = undefined;
pub var bishop_magics: [64]Magic = undefined;

pub const Slider = enum {
    Straight,
    Diagonal,
};

inline fn relevant_bits(comptime slider: Slider, square: u6) u6 {
    switch (slider) {
        Slider.Straight => return ROOK_RELEVANT_BITS[square],
        Slider.Diagonal => return BISHOP_RELEVANT_BITS[square],
    }
}

inline fn magics(comptime slider: Slider, square: u6) Magic {
    switch (slider) {
        Slider.Straight => return &rook_magics[square],
        Slider.Diagonal => return &bishop_magics[square],
    }
}

inline fn mask_rank(square: Square) Bitboard {
    return RANK_8 << (8 * square.rank());
}

inline fn mask_file(square: Square) Bitboard {
    return FILE_A << square.file();
}

fn generate_slider_attacks(comptime slider: Slider, square: Square, blocked: Bitboard) Bitboard {
    var board: Bitboard = 0;
    switch (slider) {
        Slider.Straight => {
            board |= attacks_in_direction(square, 8, blocked);
            board |= attacks_in_direction(square, -8, blocked);
            board |= attacks_in_direction(square, 1, blocked);
            board |= attacks_in_direction(square, -1, blocked);
        },
        Slider.Diagonal => {
            board |= attacks_in_direction(square, 7, blocked);
            board |= attacks_in_direction(square, -7, blocked);
            board |= attacks_in_direction(square, 9, blocked);
            board |= attacks_in_direction(square, -9, blocked);
        },
    }
    return board;
}

pub fn init_magics() void {
    init_slider_magics(Slider.Straight);
    init_slider_magics(Slider.Diagonal);
}

fn init_slider_magics(slider: Slider) void {
    var square: u6 = 0;
    var size: u32 = 0;

    var reference_attacks: [4096]Bitboard = undefined;
    var occupancies: [4096]Bitboard = undefined;

    // Utility array to prevent having to reset the hash buckets on every failed attempt.
    // (instead, we simply check if they were set in the current iteration and if not, overwrite them)
    var last_modified_at: [4096]u64 = [1]u64{0} ** 4096;

    while (true): (square += 1) {
        const s = @intToEnum(Square, square);
        const edges = ((RANK_1 | RANK_8) & ~mask_rank(s)) | ((FILE_A | FILE_H) & ~mask_file(s));

        var m = magics(slider, square).*;
        m.mask = generate_slider_attacks(slider, square, 0) & ~edges;
        m.shift = ~@as(u6, 0) - relevant_bits(slider, square);
        m.ptr = if (square == 0) 0 else magics(slider, square - 1).*.ptr + size;
        m.magic = 0;

        var i: u64 = 0;
        const occupancy_combinations = @as(u64, 1) << relevant_bits(slider, square);
        while (i < occupancy_combinations) : (i += 1) {
            occupancies[i] = populate_occupancy_map(i, m.mask, occupancy_combinations);
            reference_attacks[i] = generate_slider_attacks(slider, square, occupancies[i]);
        }

        size = occupancy_combinations;

        // find magic number
        var rng = rand.Rand64.new();
        search_magic: while (true) {
            // random number with a low number of set bits
            const magic: u64 = rng.next() & rng.next() & rng.next();

            // skip bad magic numbers
            if (@popCount((m.mask *% magic) >> 56) < 6) continue;
            m.magic = magic;

            i = 0;
            while (i < occupancy_combinations) : (i += 1) {
                const hash = m.index(occupancies[i]);

                // we use m.attacks as an array of hash buckets.
                // That way, if we find a good magic number, the attack table will already be filled

                // The epoch number is "i + 1" instead of just "i" because i starts at zero and the last_modified
                // value should be smaller but also unsigned - so we take a seperate counter that is i + 1 as the 
                // epoch number
                if (last_modified_at[hash] < i + 1) {
                    // bucket unused
                    m.attacks[hash] = reference_attacks[i];
                    last_modified_at = i + 1;
                } else if (m.attacks[hash] != reference_attacks[i]) {
                    // hash collision with different attacks, bad magic value
                    // note that we do allow hash collisions as long as they produce the same attack pattern
                    continue :search_magic;
                }
            }

            // if we haven't hit a continue yet, the magic value does not produce hash collisions
            return magic;
        }



        if (square == 63) break;
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

/// Bit mask for masking off the A file
const NOT_A_FILE: Bitboard = 0xfefefefefefefefe;
/// Bit mask for masking off the H file
pub const NOT_H_FILE: Bitboard = 0x7f7f7f7f7f7f7f7f;
/// Bit mask for masking off the A and B files
const NOT_AB_FILE: Bitboard = 0xfcfcfcfcfcfcfcfc;
/// Bit mask for masking off the G and H files
const NOT_GH_FILE: Bitboard = 0x3f3f3f3f3f3f3f3f;
/// Bit mask for masking the A file
const A_FILE: Bitboard = 0x101010101010101;
/// Bit mask for masking the first rank
const EIGTH_RANK: Bitboard = 0xff;
/// Bit mask for masking off the outer files
const NOT_AH_FILE: Bitboard = 0x7e7e7e7e7e7e7e7e;
/// Bit mask for masking off the outer ranks
const NOT_FIRST_OR_EIGTH_RANK: Bitboard = 0xffffffffffff00;

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

pub fn attacks_in_direction(start: Square, signed_shift: i5, blocked: Bitboard) Bitboard {
    const blocked_not_by_me = blocked ^ start.as_board();
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    // std.debug.print("max moves: {d}\n", .{max_moves});
    // std.debug.print("start square: {s}\n", .{@tagName(start)});
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var square = @enumToInt(start);
    // std.debug.print("is blocked here: {}\n", .{(blocked >> square) & 1 == 1});
    var attack_mask: Bitboard = 0;
    var i: u3 = 0;
    while (i < max_moves and (blocked_not_by_me >> square) & 1 == 0) : (i += 1) {
        if (negative_shift) square -= shift else square += shift;
        attack_mask |= @as(Bitboard, 1) << square;
    }
    return attack_mask;
}

fn mask_in_direction(start: Square, signed_shift: i5) Bitboard {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    if (max_moves == 0) return 0;
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var square = @enumToInt(start);
    var mask: Bitboard = 0;
    var i: u3 = 0;
    while (i < max_moves - 1) : (i += 1) {
        if (negative_shift) square -= shift else square += shift;
        mask |= @as(Bitboard, 1) << square;
    }
    return mask;
}

/// Compute the left attacks for a set of pawns
/// (Left from white's POV)
pub inline fn pawn_attacks_left(comptime color: Color, board: Bitboard) Bitboard {
    if (color == Color.white) {
        return (board & NOT_A_FILE) >> 9;
    } else {
        return (board & NOT_A_FILE) << 7;
    }
}

/// Compute the right attacks for a set of pawns
/// (Left from white's POV)
pub inline fn pawn_attacks_right(comptime color: Color, board: Bitboard) Bitboard {
    if (color == Color.white) {
        return (board & NOT_H_FILE) >> 7;
    } else {
        return (board & NOT_H_FILE) << 9;
    }
}

pub inline fn pawn_attacks(comptime color: Color, board: Bitboard) Bitboard {
    return pawn_attacks_left(color, board) | pawn_attacks_right(color, board);
}

pub fn king_attacks(board: Bitboard) Bitboard {
    return ((board & NOT_A_FILE) >> 1) // left
    | ((board & NOT_H_FILE) << 1) // right
    | (board << 8) // down
    | (board >> 8) // up
    | ((board & NOT_A_FILE) >> 9) // up left
    | ((board & NOT_H_FILE) >> 7) // up right
    | ((board & NOT_H_FILE) << 9) // down right
    | ((board & NOT_A_FILE) << 7); // down left
}

pub fn knight_attack(square: Square) Bitboard {
    return knight_attacks(square.as_board());
}

/// Take a bitboard of knights and produce a bitboard marking their attacks
pub fn knight_attacks(board: Bitboard) Bitboard {
    return ((board & NOT_A_FILE) >> 17) // up up left
    | ((board & NOT_H_FILE) >> 15) // up up right
    | ((board & NOT_GH_FILE) >> 6) // up right right
    | ((board & NOT_GH_FILE) << 10) // down right right
    | ((board & NOT_H_FILE) << 17) // down down right
    | ((board & NOT_A_FILE) << 15) // down down left
    | ((board & NOT_AB_FILE) << 6) // down left left
    | ((board & NOT_AB_FILE) >> 10); // up left left
}

/// Determine the positions whose occupancy is relevant to the moves a bishop can make
fn bishop_relevant_positions(square: Square) Bitboard {
    var board: u64 = 0;
    board |= mask_in_direction(square, 7);
    board |= mask_in_direction(square, -7);
    board |= mask_in_direction(square, 9);
    board |= mask_in_direction(square, -9);
    return board;
}

/// Determine the positions whose occupancy is relevant to the moves a rook can make
pub fn rook_relevant_positions(square: Square) Bitboard {
    var board: Bitboard = 0;
    board |= (A_FILE << square.file()) & NOT_FIRST_OR_EIGTH_RANK;
    board |= (EIGTH_RANK << (@enumToInt(square) & ~@as(u6, 0b111))) & NOT_AH_FILE;
    board ^= square.as_board(); // the rooks position itself is not relevant
    return board;
}


fn populate_occupancy_map(index_: Bitboard, attack_map_: Bitboard, num_bits: u6) Bitboard {
    var index = index_;
    var attack_map: Bitboard = attack_map_;
    var occupied: Bitboard = 0;
    var count: u6 = 0;
    while (count < num_bits) : (count += 1) {
        // continously pop the ls1b
        // truncate is safe here because there because we will never reach attack_map = 0
        const square = get_lsb_square(attack_map);
        attack_map ^= square.as_board();

        if (index & 1 != 0) {
            occupied |= square.as_board();
        }
        index >>= 1;
    }
    return occupied;
}

fn find_magic_number(square: Square, num_relevant_positions: u6, comptime bishop: bool) Bitboard {
    var attacks: [4096]Bitboard = undefined;
    var occupancies: [4096]Bitboard = undefined;
    const occupancy_mask = if (bishop) bishop_relevant_positions(square) else rook_relevant_positions(square);
    const num_blocking_combinations: u64 = @as(u64, 1) << num_relevant_positions;

    // populate attack/occupancy tables
    var i: u64 = 0;
    while (i < num_blocking_combinations) : (i += 1) {
        occupancies[i] = populate_occupancy_map(i, occupancy_mask, num_relevant_positions);
        attacks[i] = if (bishop) generate_bishop_attacks(square, occupancies[i]) else generate_rook_attacks(square, occupancies[i]);
    }

}

pub fn bishop_attacks(square: Square, blocked: Bitboard) Bitboard {
    // mask off the pieces we don't care about
    const relevant_blocks = blocked & bishop_blocking_positions[@enumToInt(square)];
    const hash = (relevant_blocks *% magics.BISHOP_MAGIC_NUMBERS[@enumToInt(square)]) >> (~BISHOP_RELEVANT_BITS[@enumToInt(square)] + 1);
    return bishop_attack_table[@enumToInt(square)][hash];
}

pub fn rook_attacks(square: Square, blocked: Bitboard) Bitboard {
    // mask off the pieces we don't care about
    const relevant_blocks = blocked & rook_blocking_positions[@enumToInt(square)];
    const hash = (relevant_blocks *% magics.ROOK_MAGIC_NUMBERS[@enumToInt(square)]) >> (~ROOK_RELEVANT_BITS[@enumToInt(square)] + 1);
    return rook_attack_table[@enumToInt(square)][hash];
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

test "rook attacks" {
    const expectEqual = std.testing.expectEqual;

    // D4, C4, D1, D7 and G6 blocked
    const blocked = 0x800000400400800;
    try expectEqual(rook_attacks(Square.D4, blocked), 0x80808f408080800);

    try expectEqual(rook_attacks(Square.A1, 0), 0xfe01010101010101);
}

test "bishop attacks" {
    const expectEqual = std.testing.expectEqual;

    // D4, C5, F6, G1 and G3 blocked
    const blocked = 0x4000052000000;
    try expectEqual(bishop_attacks(Square.D4, blocked), 0x4122140014200000);

    try expectEqual(bishop_attacks(Square.A1, 0), 0x2040810204080);
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
