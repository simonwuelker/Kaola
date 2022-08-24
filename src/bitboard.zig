const std = @import("std");
const bitops = @import("bitops.zig");
const rand = @import("rand.zig");
const magics = @import("magics.zig");

pub fn print_bitboard(board: u64) void {
    var i: u6 = 0;
    while (i < 8): (i += 1) {
        std.debug.print("{d}  ", .{8-i});
        var j: u6 = 0;
        while (j < 8): (j += 1) {
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

const BISHOP_RELEVANT_BITS = [64]u6 {
    6, 5, 5, 5, 5, 5, 5, 6, 
    5, 5, 5, 5, 5, 5, 5, 5, 
    5, 5, 7, 7, 7, 7, 5, 5, 
    5, 5, 7, 9, 9, 7, 5, 5, 
    5, 5, 7, 9, 9, 7, 5, 5, 
    5, 5, 7, 7, 7, 7, 5, 5, 
    5, 5, 5, 5, 5, 5, 5, 5, 
    6, 5, 5, 5, 5, 5, 5, 6,
};

const ROOK_RELEVANT_BITS = [64]u6 {
    12, 11, 11, 11, 11, 11, 11, 12, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    11, 10, 10, 10, 10, 10, 10, 11, 
    12, 11, 11, 11, 11, 11, 11, 12,
};

/// Bit mask for masking off the A file
const NOT_A_FILE: u64 = 0xfefefefefefefefe;
/// Bit mask for masking off the H file
const NOT_H_FILE: u64 = 0x7f7f7f7f7f7f7f7f;
/// Bit mask for masking off the A and B files
const NOT_AB_FILE: u64 = 0xfcfcfcfcfcfcfcfc;
/// Bit mask for masking off the G and H files
const NOT_GH_FILE: u64 = 0x3f3f3f3f3f3f3f3f;
/// Bit mask for masking the A file
const A_FILE: u64 = 0x101010101010101;
/// Bit mask for masking the first rank
const EIGTH_RANK: u64 = 0xff;
/// Bit mask for masking off the outer files
const NOT_AH_FILE: u64 = 0x7e7e7e7e7e7e7e7e;
/// Bit mask for masking off the outer ranks
const NOT_FIRST_OR_EIGTH_RANK: u64 = 0xffffffffffff00;

fn bitboard_distance_to_edge(field: u6, shift: i5) u3 {
    return switch (shift) {
        1 => @as(u3, 7) - file(field),
        -1 => file(field),
        8 => @as(u3, 7) - rank(field),
        -8 => rank(field),
        9 => std.math.min(@as(u3, 7) - file(field), @as(u6, 7) - rank(field)),
        -7 => std.math.min(@as(u3, 7) - file(field), rank(field)),
        -9 => std.math.min(file(field), rank(field)),
        7 => std.math.min(file(field), @as(u3, 7) - rank(field)),
        else => unreachable,
    };
}

fn attacks_in_direction(start: u6, signed_shift: i5, blocked: u64) u64 {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var field = start;
    var attack_mask: u64 = 0;
    var i: u3 = 0;
    while (i < max_moves and (blocked >> field) & 1 == 0): (i += 1) {
        if (negative_shift) field -= shift else field += shift;
        attack_mask |= @as(u64, 1) << field;
    }
    return attack_mask;
}

fn mask_in_direction(start: u6, signed_shift: i5) u64 {
    const max_moves = bitboard_distance_to_edge(start, signed_shift);
    if (max_moves == 0) return 0;
    const negative_shift = if (signed_shift < 0) true else false;
    const shift: u5 = std.math.absCast(signed_shift);
    var field = start;
    var mask: u64 = 0;
    var i: u3 = 0;
    while (i < max_moves - 1): (i += 1) {
        if (negative_shift) field -= shift else field += shift;
        mask |= @as(u64, 1) << field;
    }
    return mask;
}

/// Compute the left attacks for a set of white pawns
/// (Left from white's POV)
pub fn white_pawn_attacks_left(board: u64) callconv (.Inline) u64 {
    return (board & NOT_A_FILE) >> 9;
}

/// Compute the right attacks for a set of white pawns
/// (Left from white's POV)
pub fn white_pawn_attacks_right(board: u64) callconv (.Inline) u64 {
    return (board & NOT_H_FILE) >> 7;
}

/// Compute the left attacks for a set of black pawns
/// (Left from white's POV)
pub fn black_pawn_attacks_left(board: u64) callconv (.Inline) u64 {
    return (board & NOT_A_FILE) << 7;
}

/// Compute the right attacks for a set of black pawns
/// (Left from white's POV)
pub fn black_pawn_attacks_right(board: u64) callconv (.Inline) u64 {
    return (board & NOT_H_FILE) << 9;
}

pub fn white_pawn_attacks(board: u64) callconv (.Inline) u64 {
    return white_pawn_attacks_left(board) | white_pawn_attacks_right(board);
}

pub fn black_pawn_attacks(board: u64) callconv (.Inline) u64 {
    return black_pawn_attacks_left(board) | black_pawn_attacks_right(board);
}

pub fn king_attacks(board: u64) u64 {
    return ((board & NOT_A_FILE) >> 1) // left
        | ((board & NOT_H_FILE) << 1) // right
        | (board << 8) // down
        | (board >> 8) // up
        | ((board & NOT_A_FILE) >> 9) // up left
        | ((board & NOT_H_FILE) >> 7) // up right
        | ((board & NOT_H_FILE) << 9) // down right
        | ((board & NOT_A_FILE) << 7); // down left
}

pub fn single_knight_attack(field: u6) u64 {
    const board: u64 = @as(u64, 1) << field;
    return knight_attacks(board);
}

/// Take a bitboard of knights and produce a bitboard marking their attacks
pub fn knight_attacks(board: u64) u64 {
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
fn bishop_relevant_positions(field: u6) u64 {
    var board: u64 = 0;
    board |= mask_in_direction(field, 7);
    board |= mask_in_direction(field, -7);
    board |= mask_in_direction(field, 9);
    board |= mask_in_direction(field, -9);
    return board;
}

/// Determine the positions whose occupancy is relevant to the moves a rook can make
fn rook_relevant_positions(field: u6) u64 {
    var board: u64 = 0;
    board |= (A_FILE << field % 8) & NOT_FIRST_OR_EIGTH_RANK;
    board |= (EIGTH_RANK << (field & ~@as(u6, 7))) & NOT_AH_FILE;
    board ^= @as(u64, 1) << field;
    return board;
}

fn generate_bishop_attacks(field: u6, blocked: u64) u64 {
    var board: u64 = 0;
    board |= attacks_in_direction(field, 7, blocked);
    board |= attacks_in_direction(field, -7, blocked);
    board |= attacks_in_direction(field, 9, blocked);
    board |= attacks_in_direction(field, -9, blocked);
    return board;
}

fn generate_rook_attacks(field: u6, blocked: u64) u64 {
    var board: u64 = 0;
    board |= attacks_in_direction(field, 8, blocked);
    board |= attacks_in_direction(field, -8, blocked);
    board |= attacks_in_direction(field, 1, blocked);
    board |= attacks_in_direction(field, -1, blocked);
    return board;
}

fn populate_occupancy_map(index_: u64, attack_map_: u64, num_bits: u6) u64 {
    var index = index_;
    var attack_map: u64 = attack_map_;
    var occupied: u64 = 0;
    var count: u6 = 0;
    while (count < num_bits): (count += 1) {
        // continously pop the ls1b
        var square: u6 = bitops.ls1b_index(attack_map);
        attack_map ^= @as(u64, 1) << square;

        if (index & 1 != 0) {
            occupied |= @as(u64, 1) << square;
        }
        index >>= 1;
    }
    return occupied;
}

fn find_magic_number(square: u6, num_relevant_positions: u6, bishop: bool) u64 {
    var attacks: [4096]u64 = undefined;
    var occupancies: [4096]u64 = undefined;
    const occupancy_mask = if (bishop) bishop_relevant_positions(square) else rook_relevant_positions(square);
    const num_blocking_combinations: u64 = @as(u64, 1) << num_relevant_positions;

    // populate attack/occupancy tables
    var i: u64 = 0;
    while (i < num_blocking_combinations): (i += 1) {
        occupancies[i] = populate_occupancy_map(i, occupancy_mask, num_relevant_positions);
        attacks[i] = if (bishop) generate_bishop_attacks(square, occupancies[i]) else generate_rook_attacks(square, occupancies[i]);
    }

    // find magic number
    var rng = rand.Rand64.new();
    search_magic: while(true) {
        // random number with a low number of set bits
        const magic: u64 = rng.next() & rng.next() & rng.next();

        // skip bad magic numbers
        if (@popCount(u64, (occupancy_mask *% magic) >> 56) < 6) {
            continue;
        }

        var hash_buckets: [4096]u64 = [1]u64 { 0 } ** 4096;
        std.mem.set(u64, hash_buckets[0..hash_buckets.len], 0);

        var index: u64 = 0;
        while(index < num_blocking_combinations): (index += 1) {
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

var bishop_attack_table: [64][512]u64 = undefined;
var bishop_blocking_positions: [64]u64 = undefined;
var rook_attack_table: [64][4096]u64 = undefined;
var rook_blocking_positions: [64]u64 = undefined;

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
    var square: u6 = 0;
    while (square < 63): (square += 1) {
        const relevant_positions = bishop_relevant_positions(square);
        bishop_blocking_positions[square] = relevant_positions;
        const num_positions: u6 = BISHOP_RELEVANT_BITS[square];
        var index: u64 = 0;
        while(index < @as(u64, 1) << num_positions): (index += 1) {
            const blocked: u64 = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% magics.BISHOP_MAGIC_NUMBERS[square]) >> (~num_positions + 1);
            bishop_attack_table[square][hash] = generate_bishop_attacks(square, blocked);
        }
    }
    square = 0;
    while (square < 63): (square += 1) {
        const relevant_positions = rook_relevant_positions(square);
        rook_blocking_positions[square] = relevant_positions;
        const num_positions: u6 = ROOK_RELEVANT_BITS[square];
        var index: u64 = 0;
        while(index < @as(u64, 1) << num_positions): (index += 1) {
            const blocked: u64 = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% magics.ROOK_MAGIC_NUMBERS[square]) >> (~num_positions + 1);
            rook_attack_table[square][hash] = generate_rook_attacks(square, blocked);
        }
    }
}

pub fn bishop_attacks(square: u6, blocked: u64) u64 {
    // mask off the pieces we don't care about
    const relevant_blocks = blocked & bishop_blocking_positions[square];
    const hash = (relevant_blocks *% magics.BISHOP_MAGIC_NUMBERS[square]) >> (~BISHOP_RELEVANT_BITS[square] + 1);
    return bishop_attack_table[square][hash];
}

pub fn rook_attacks(square: u6, blocked: u64) u64 {
    // mask off the pieces we don't care about
    const relevant_blocks = blocked & rook_blocking_positions[square];
    const hash = (relevant_blocks *% magics.ROOK_MAGIC_NUMBERS[square]) >> (~ROOK_RELEVANT_BITS[square] + 1);
    return rook_attack_table[square][hash];
}

pub fn queen_attacks(square: u6, blocked: u64) u64 {
    return bishop_attacks(square, blocked) | rook_attacks(square, blocked);
}

/// A lookup table containing the paths between any two squares on the board.
/// Source square is included, target square is not.
/// The table should be indexed like this: `PATH_BETWEEN_SQUARES[source][target]`.
pub var PATH_BETWEEN_SQUARES: [64][64]u64 = undefined;

pub fn init_paths_between_squares() void {
    var source: u6 = 0;
    while (true): (source += 1) {
        var target: u6 = 0;
        while (true): (target += 1) {
            if (source == target) PATH_BETWEEN_SQUARES[source][target] = 0;

            const blocked = @as(u64, 1) << source | @as(u64, 1) << target;
            // if horizontally aligned
            if (rank(source) == rank(target) or file(source) == file(target)) {
                PATH_BETWEEN_SQUARES[source][target] = rook_attacks(source, blocked) & rook_attacks(target, blocked);
                PATH_BETWEEN_SQUARES[source][target] ^= @as(u64, 1) << source;
            }
            // if diagonally aligned (if the absolute difference between their ranks is the same as their files
            else if (std.math.max(rank(source), rank(target)) - std.math.min(rank(source), rank(target)) ==
                    std.math.max(file(source), file(target)) - std.math.min(file(source), file(target))) {
                PATH_BETWEEN_SQUARES[source][target] = bishop_attacks(source, blocked) & bishop_attacks(target, blocked);
                PATH_BETWEEN_SQUARES[source][target] ^= @as(u64, 1) << source;
            } else {
                // no straight path => 0
                PATH_BETWEEN_SQUARES[source][target] = 0;
            }
            if (target == 63) break;
        }

        if (source == 63) break;
    }
}

pub fn file(square: u6) callconv(.Inline) u3 {
    return @intCast(u3, square & 0b111);
}

pub fn rank(square: u6) callconv(.Inline) u3 {
    return @intCast(u3, square >> 3);
}
