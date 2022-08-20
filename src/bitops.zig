const std = @import("std");

const LSB_64_table = [_]u6 {
   22,  0,  0,  0, 30,  0,  0, 38, 18,  0, 16, 15, 17,  0, 46,  9, 19,  8,  7, 10,
    0, 63,  1, 56, 55, 57,  2, 11,  0, 58,  0,  0, 20,  0,  3,  0,  0, 59,  0,  0,
    0,  0,  0, 12,  0,  0,  0,  0,  0,  0,  4,  0,  0, 60,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0, 21,  0,  0,  0, 29,  0,  0, 37,  0,  0,  0, 13,  0,  0, 45,  0,
    0,  0,  5,  0,  0, 61,  0,  0,  0, 53,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   28,  0,  0, 36,  0,  0,  0,  0,  0,  0, 44,  0,  0,  0,  0,  0, 27,  0,  0, 35,
    0, 52,  0,  0, 26,  0, 43, 34, 25, 23, 24, 33, 31, 32, 42, 39, 40, 51, 41, 14,
    0, 49, 47, 48,  0, 50,  6,  0,  0, 62,  0,  0,  0, 54
};

pub fn count_bits(board_: u64) u6 {
    var board = board_;
    var count: u6 = 0;
    while (board != 0): (count += 1){
        pop_ls1b(&board);
    }
    return count;
}

pub fn ls1b_index(board_: u64) u6 {
   std.debug.assert(board_ != 0); // must contain at least one set bit for the result to make sense
   var board = board_;
   board  ^= board - 1;
   var t32  = @truncate(u32, board) ^ @truncate(u32, board >> 32);
   t32 ^= 0x01C5FC81;
   t32 +=  t32 >> 16;
   t32 -= (t32 >> 8) + 51;
   return LSB_64_table [t32 & 255]; // 0..63
}

pub fn pop_ls1b(num: *u64) void {
    num.* &= num.* - 1;
}
