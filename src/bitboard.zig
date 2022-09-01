//! Contains regular and magic bitboards 
//! as well as attack generation code

const std = @import("std");
const bitops = @import("bitops.zig");
const board_module = @import("board.zig");
const Square = board_module.Square;
const Color = board_module.Color;
const rand = @import("rand.zig");
const magics = @import("magics.zig");

pub const Bitboard = u64;

pub fn print_bitboard(board: Bitboard, title: []const u8) void {
    std.debug.print("\n==> {s}\n", .{title});
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
const NOT_H_FILE: Bitboard = 0x7f7f7f7f7f7f7f7f;
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
    return @intToEnum(Square, @ctz(Bitboard, board));
}

fn attacks_in_direction(start: Square, signed_shift: i5, blocked: Bitboard) Bitboard {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var square = @enumToInt(start);
    var attack_mask: u64 = 0;
    var i: u3 = 0;
    while (i < max_moves and (blocked >> square) & 1 == 0) : (i += 1) {
        if (negative_shift) square -= shift else square += shift;
        attack_mask |= @as(u64, 1) << square;
    }
    return attack_mask;
}

fn mask_in_direction(start: Square, signed_shift: i5) Bitboard {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    if (max_moves == 0) return 0;
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var square = @enumToInt(start);
    var mask: u64 = 0;
    var i: u3 = 0;
    while (i < max_moves - 1) : (i += 1) {
        if (negative_shift) square -= shift else square += shift;
        mask |= @as(u64, 1) << square;
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
fn rook_relevant_positions(square: Square) Bitboard {
    var board: Bitboard = 0;
    board |= (A_FILE << square.file()) & NOT_FIRST_OR_EIGTH_RANK;
    board |= (EIGTH_RANK << (square.rank())) & NOT_AH_FILE;
    board ^= square.as_board(); // the rooks position itself is not relevant
    return board;
}

fn generate_bishop_attacks(square: Square, blocked: Bitboard) Bitboard {
    var board: u64 = 0;
    board |= attacks_in_direction(square, 7, blocked);
    board |= attacks_in_direction(square, -7, blocked);
    board |= attacks_in_direction(square, 9, blocked);
    board |= attacks_in_direction(square, -9, blocked);
    return board;
}

fn generate_rook_attacks(square: Square, blocked: Bitboard) Bitboard {
    var board: u64 = 0;
    board |= attacks_in_direction(square, 8, blocked);
    board |= attacks_in_direction(square, -8, blocked);
    board |= attacks_in_direction(square, 1, blocked);
    board |= attacks_in_direction(square, -1, blocked);
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

fn find_magic_number(square: u6, num_relevant_positions: u6, bishop: bool) Bitboard {
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

    // find magic number
    var rng = rand.Rand64.new();
    search_magic: while (true) {
        // random number with a low number of set bits
        const magic: u64 = rng.next() & rng.next() & rng.next();

        // skip bad magic numbers
        if (@popCount(u64, (occupancy_mask *% magic) >> 56) < 6) {
            continue;
        }

        var hash_buckets: [4096]u64 = [1]u64{0} ** 4096;
        std.mem.set(u64, hash_buckets[0..hash_buckets.len], 0);

        var index: u64 = 0;
        while (index < num_blocking_combinations) : (index += 1) {
            var hash: u64 = (occupancies[index] *% magic) >> (~num_relevant_positions + 1);
            if (hash_buckets[hash] == 0) {
                // bucket unused
                hash_buckets[hash] = attacks[index];
            } else if (hash_buckets[hash] != attacks[index]) {
                // hash collision with different attacks, bad magic value
                // note that we do allow hash collisions as long as they produce the same attack pattern
                // std.debug.print("collission at {d}\n", .{index});
                continue :search_magic;
            }
        }

        // if we haven't hit a continue yet, the magic value does not produce hash collisions
        return magic;
    }
}

var bishop_attack_table: [64][512]Bitboard = undefined;
var bishop_blocking_positions: [64]Bitboard = undefined;
var rook_attack_table: [64][4096]Bitboard = undefined;
var rook_blocking_positions: [64]Bitboard = undefined;

fn init_magic_numbers() void {
    var square: u6 = 0;
    while (square < 63) : (square += 1) {
        // bishop_magic_numbers[square] = find_magic_number(square, BISHOP_RELEVANT_BITS[square], true);
        // rook_magic_numbers[square] = find_magic_number(square, ROOK_RELEVANT_BITS[square], false);
        std.debug.print("0x{x}\n", .{find_magic_number(square, ROOK_RELEVANT_BITS[square], false)});
    }
    // TODO: find out how to do this properly in zig
    std.debug.print("0x{x}\n", .{find_magic_number(0, ROOK_RELEVANT_BITS[0], false)});
}

pub fn init_slider_attacks() void {
    var square_index: u6 = 0;
    while (square_index < 63) : (square_index += 1) {
        const square = @intToEnum(Square, square_index);
        const relevant_positions = bishop_relevant_positions(square);
        bishop_blocking_positions[square_index] = relevant_positions;
        const num_positions: u6 = BISHOP_RELEVANT_BITS[square_index];
        var index: u64 = 0;
        while (index < @as(u64, 1) << num_positions) : (index += 1) {
            const blocked: Bitboard = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% magics.BISHOP_MAGIC_NUMBERS[square_index]) >> (~num_positions + 1);
            bishop_attack_table[square_index][hash] = generate_bishop_attacks(square, blocked);
        }
    }
    square_index = 0;
    while (square_index < 63) : (square_index += 1) {
        const square = @intToEnum(Square, square_index);
        const relevant_positions = rook_relevant_positions(square);
        rook_blocking_positions[square_index] = relevant_positions;
        const num_positions: u6 = ROOK_RELEVANT_BITS[square_index];
        var index: u64 = 0;
        while (index < @as(u64, 1) << num_positions) : (index += 1) {
            const blocked: Bitboard = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% magics.ROOK_MAGIC_NUMBERS[square_index]) >> (~num_positions + 1);
            rook_attack_table[square_index][hash] = generate_rook_attacks(square, blocked);
        }
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

