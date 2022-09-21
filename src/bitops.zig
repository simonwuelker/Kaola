//! Contains bit manipulation utility functions

const builtin = @import("builtin");
const std = @import("std");
const x86 = std.Target.x86;
const Cpu = std.Target.Cpu;

const bitboard = @import("bitboard.zig");

/// Unset the least-significant set bit in a given number
pub inline fn pop_ls1b(num: *u64) void {
    num.* &= num.* - 1;
}

/// Check whether the target supports the [PEXT](https://www.felixcloutier.com/x86/pext) instruction,
/// specifically whether BMI2 is implemented in 64 bit mode.
pub fn has_pext() bool {
    return builtin.cpu.arch == Cpu.Arch.x86_64 and x86.featureSetHas(builtin.cpu.features, x86.Feature.bmi2);
}

pub fn pext(src: usize, mask: usize) usize {
    std.debug.assert(has_pext());
    return asm ("pext %[src], %[mask], %[ret]"
        :[ret] "=r" (-> usize)
        :[src] "r" (src),
         [mask] "r" (mask),

    );
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
