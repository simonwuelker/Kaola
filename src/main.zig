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

fn pawn_attacks(board: u64, is_white: bool) u64 {
    return if (is_white) {
        return ((board & NOT_A_FILE) >> 9) | ((board & NOT_H_FILE) >> 7);
    } else {
        return ((board & NOT_A_FILE) << 7) | ((board & NOT_H_FILE) << 9);
    };
}

fn king_attacks(board: u64) u64 {
    return ((board & NOT_A_FILE) >> 1) // left
        | ((board & NOT_H_FILE) << 1) // right
        | (board << 8) // down
        | (board >> 8) // up
        | ((board & NOT_A_FILE) >> 9) // up left
        | ((board & NOT_H_FILE) >> 7) // up right
        | ((board & NOT_H_FILE) << 9) // down right
        | ((board & NOT_A_FILE) << 7); // down left
}

fn knight_attacks(board: u64) u64 {
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
fn bishop_relevant_positions(field: Field) u64 {
    var board: u64 = 0;
    var piece_file = @enumToInt(field) % 8;
    var piece_rank = @enumToInt(field) / 8;

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
    return board;
}

fn bishop_attacks(field: Field) u64 {
    var board: u64 = 0;
    var piece_file = @enumToInt(field) % 8;
    var piece_rank = @enumToInt(field) / 8;

    var file = piece_file;
    var rank = piece_rank;
    while ((file >= 0) and (rank >= 0)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        if (file == 0 or rank == 0) {
            break;
        }
        file -= 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file <= 7) and (rank <= 7)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        file += 1;
        rank += 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file <= 7) and (rank >= 0)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        if (rank == 0) {
            break;
        }
        file += 1;
        rank -= 1;
    }

    file = piece_file;
    rank = piece_rank;
    while ((file >= 0) and (rank <= 7)) {
        set_bit(&board, @intToEnum(Field, rank * 8 + file));
        if (file == 0) {
            break;
        }
        file -= 1;
        rank += 1;
    }
    return board;
}


// fn populate_occupancy_map(index: u64, attack_map: u64) u64 {
// }


fn set_bit(board: *u64, index: Field) void {
    board.* |= @as(u64, 1) << @enumToInt(index);
}

pub fn main() !void {
    print_bitboard(bishop_attacks(Field.E4));
    var x: u64 = 5;
    var c: u8 = 0;
    while (c < 60) : (c += 1){
        std.debug.print("{d} {b} \n", .{util.ls1b_index(x), x});
        x <<= 1;
    }
}
