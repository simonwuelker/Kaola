const std = @import("std");
const rand = @import("rand.zig");
const util = @import("util.zig");

const Field = enum(u6) {
    A8, B8, C8, D8, E8, F8, G8, H8,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A1, B1, C1, D1, E1, F1, G1, H1,
};

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

fn print_bitboard(board: u64) void {
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

fn pawn_attacks(field: u6, is_white: bool) u64 {
    const board: u64 = 1 << field;
    return if (is_white) {
        return ((board & NOT_A_FILE) >> 9) | ((board & NOT_H_FILE) >> 7);
    } else {
        return ((board & NOT_A_FILE) << 7) | ((board & NOT_H_FILE) << 9);
    };
}

fn king_attacks(field: u6) u64 {
    const board: u64 = 1 << field;
    return ((board & NOT_A_FILE) >> 1) // left
        | ((board & NOT_H_FILE) << 1) // right
        | (board << 8) // down
        | (board >> 8) // up
        | ((board & NOT_A_FILE) >> 9) // up left
        | ((board & NOT_H_FILE) >> 7) // up right
        | ((board & NOT_H_FILE) << 9) // down right
        | ((board & NOT_A_FILE) << 7); // down left
}

fn knight_attacks(field: u6) u64 {
    const board: u64 = 1 << field;
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
    var piece_file = field % 8;
    var piece_rank = field / 8;

    var file = piece_file;
    var rank = piece_rank;
    while ((file > 0) and (rank > 0)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        file -= 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file < 7) and (rank < 7)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        file += 1;
        rank += 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file < 7) and (rank > 0)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        file += 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file > 0) and (rank < 7)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        file -= 1;
        rank += 1;
    }
    // unset the original bishop bit - makes the code simpler and efficiency isn't that important,
    // this will only be called at startup :^)
    board ^= @as(u64, 1) << field;
    return board;
}

/// Determine the positions whose occupancy is relevant to the moves a rook can make
fn rook_relevant_positions(field: u6) u64 {
    var board: u64 = 0;
    var piece_file = field % 8;
    var piece_rank = field / 8;

    var file = piece_file;
    while (file > 0): (file -= 1) {
        set_bit(&board, @intToEnum(Field, piece_rank * 8 + file));
    }

    file = piece_file;
    while (file < 7): (file += 1) {
        set_bit(&board, @intToEnum(Field, piece_rank * 8 + file));
    }

    var rank = piece_rank;
    while (rank > 0): (rank -= 1) {
        set_bit(&board, @intToEnum(Field, rank * 8 + piece_file));
    }

    rank = piece_rank;
    while (rank < 7): (rank += 1) {
        set_bit(&board, @intToEnum(Field, rank * 8 + piece_file));
    }


    // unset the original rook bit - makes the code simpler and efficiency isn't that important,
    // this will only be called at startup :^)
    board ^= @as(u64, 1) << field;
    return board;
}

fn generate_bishop_attacks(field: u6, blocked: u64) u64 {
    var board: u64 = 0;
    var piece_file = field % 8;
    var piece_rank = field / 8;

    var file = piece_file;
    var rank = piece_rank;
    while ((file >= 0) and (rank >= 0)) {
        const index = rank * 8 + file;
        set_bit(&board, @intToEnum(Field, index));
        if (file == 0 or rank == 0 or blocked >> index & 1 != 0) {
            break;
        }
        file -= 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file <= 7) and (rank <= 7)) {
        const index = rank * 8 + file;
        set_bit(&board, @intToEnum(Field, index));
        if (blocked >> index & 1 != 0) {
            break;
        }
        file += 1;
        rank += 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file <= 7) and (rank >= 0)) {
        const index = rank * 8 + file;
        set_bit(&board, @intToEnum(Field, index));
        if (rank == 0 or blocked >> index & 1 != 0) {
            break;
        }
        file += 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file >= 0) and (rank <= 7)) {
        const index = rank * 8 + file;
        set_bit(&board, @intToEnum(Field, index));
        if (file == 0 or blocked >> index & 1 != 0) {
            break;
        }
        file -= 1;
        rank += 1;
    }
    // unset the original bishop bit - makes the code simpler and efficiency isn't that important,
    // this will only be called at startup :^)
    board ^= @as(u64, 1) << field;
    return board;
}

fn generate_rook_attacks(field: u6, blocked: u64) u64 {
    var board: u64 = 0;
    var piece_file = field % 8;
    var piece_rank = field / 8;

    var file = piece_file;
    while (true): (file -= 1) {
        const index = piece_rank * 8 + file;
        set_bit(&board, @intToEnum(Field, index));
        if (blocked & @as(u64, 1) << index != 0 or file == 0) {
            break;
        }
    }

    file = piece_file;
    while (true): (file += 1) {
        const index = piece_rank * 8 + file;
        set_bit(&board, @intToEnum(Field, piece_rank * 8 + file));
        if (blocked & @as(u64, 1) << index != 0 or file == 7) {
            break;
        }
    }

    var rank = piece_rank;
    while (true): (rank -= 1) {
        const index = rank * 8 + piece_file;
        set_bit(&board, @intToEnum(Field, index));
        if (blocked & @as(u64, 1) << index != 0 or rank == 0) {
            break;
        }
    }

    rank = piece_rank;
    while (true): (rank += 1) {
        const index = rank * 8 + piece_file;
        set_bit(&board, @intToEnum(Field, index));
        if (blocked & @as(u64, 1) << index != 0 or rank == 7) {
            break;
        }
    }


    // unset the original rook bit - makes the code simpler and efficiency isn't that important,
    // this will only be called at startup :^)
    board ^= @as(u64, 1) << field;
    return board;
}

fn populate_occupancy_map(index: u64, attack_map_: u64, num_bits: u6) u64 {
    var attack_map: u64 = attack_map_;
    var occupied: u64 = 0;
    var count: u6 = 0;
    while (count < num_bits): (count += 1) {
        // continously pop the ls1b
        var square: u6 = util.ls1b_index(attack_map);
        attack_map ^= @as(u64, 1) << square;

        if (index & @as(u64, 1) << count != 0) {
            occupied |= @as(u64, 1) << square;
        }
    }
    return occupied;
}

fn find_magic_number(square: u6, num_relevant_positions: u6, bishop: bool) u64 {
    var attacks: [4096]u64 = undefined;
    var occupancies: [4096]u64 = undefined;
    const occupancy_mask = if (bishop) bishop_relevant_positions(square) else rook_relevant_positions(square);
    const num_blocking_combinations: u64 = @as(u64, 1) << num_relevant_positions;

    // populate attack/occupancy map
    var i: u64 = 0;
    while (i < num_blocking_combinations): (i += 1) {
        occupancies[i] = populate_occupancy_map(i, occupancy_mask, num_relevant_positions);
        attacks[i] = if (bishop) generate_bishop_attacks(square, occupancies[i]) else generate_rook_attacks(square, occupancies[i]);
    }

    // find magic number
    var rng = rand.Rand64.new();
    var hash_buckets: [4096]u64 = undefined;
    std.debug.print("searching", .{});
    search_magic: while(true) {
        // random number with a low number of set bits
        const magic: u64 = rng.next() | rng.next() | rng.next();

        // skip bad magic numbers
        if (util.count_bits((occupancy_mask *% magic) & 0xFF00000000000000) < 6) {
            continue;
        }

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
                continue :search_magic;
            }
        }

        // if we haven't hit a continue yet, the magic value does not produce hash collisions
        return magic;
    }
}

var bishop_magic_numbers: [64]u64 = undefined;
var bishop_attack_table: [64][512]u64 = undefined;
var rook_magic_numbers: [64]u64 = undefined;
var rook_attack_table: [64][4096]u64 = undefined;

fn init_magic_numbers() void {
    var square: u6 = 0;
    while (square < 63) : (square += 1) {
        std.debug.print("searching magic for square {d}\n", .{square});
        bishop_magic_numbers[square] = find_magic_number(square, BISHOP_RELEVANT_BITS[square], true);
        rook_magic_numbers[square] = find_magic_number(square, ROOK_RELEVANT_BITS[square], false);
    }
}

fn init_slider_attacks() void {
    var square: u6 = 0;
    while (square < 63): (square += 1) {
        const relevant_positions = bishop_relevant_positions(square);
        const num_positions: u6 = BISHOP_RELEVANT_BITS[square];
        var index: u64 = 0;
        while(index < @as(u64, 1) << num_positions): (index += 1) {
            const blocked: u64 = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% bishop_magic_numbers[square]) >> (~num_positions + 1);
            bishop_attack_table[square][hash] = generate_bishop_attacks(square, blocked);
        }
    }
    square = 0;
    while (square < 63): (square += 1) {
        const relevant_positions = rook_relevant_positions(square);
        const num_positions: u6 = ROOK_RELEVANT_BITS[square];
        var index: u64 = 0;
        while(index < @as(u64, 1) << num_positions): (index += 1) {
            const blocked: u64 = populate_occupancy_map(index, relevant_positions, num_positions);
            const hash = (blocked *% rook_magic_numbers[square]) >> (~num_positions + 1);
            rook_attack_table[square][hash] = generate_rook_attacks(square, blocked);
        }
    }
}

fn bishop_attacks(square: u6, blocked: u64) u64 {
    const hash = (blocked *% bishop_magic_numbers[square]) >> (~BISHOP_RELEVANT_BITS[square] + 1);
    return bishop_attack_table[square][hash];
}

fn rook_attacks(square: u6, blocked: u64) u64 {
    const hash = (blocked *% rook_magic_numbers[square]) >> (~ROOK_RELEVANT_BITS[square] + 1);
    return rook_attack_table[square][hash];
}

fn set_bit(board: *u64, index: Field) void {
    board.* |= @as(u64, 1) << @enumToInt(index);
}

pub fn main() !void {
    init_magic_numbers();
    init_slider_attacks();

    var blocked: u64 = 0;
    set_bit(&blocked, Field.E7);
    print_bitboard(generate_rook_attacks(@enumToInt(Field.E4), blocked));
    print_bitboard(rook_attacks(@enumToInt(Field.E4), blocked));
    // print_bitboard(rook_relevant_positions(@enumToInt(Field.E4)));
}
