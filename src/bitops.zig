//! Contains bit manipulation utility functions

const std = @import("std");
const bitboard = @import("bitboard.zig");

/// Unset the least-significant set bit in a given number
pub inline fn pop_ls1b(num: *u64) void {
    num.* &= num.* - 1;
}

test "pop ls1b" {
    const expectEqual = std.testing.expectEqual;
    var x: u64 = ~@as(u64, 0);
    var count: u6 = 0;

    while (count < 63) : (count += 1) {
        const expected = ~@as(u64, 0) >> count << count; // inefficient but intuitive way to pop ls1b
        try expectEqual(expected, x);
        pop_ls1b(&x);
    }
}
