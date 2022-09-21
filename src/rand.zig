const std = @import("std");

/// Xorshift64 Random Number Generator
pub const Rand64 = struct {
    state: u64,

    const Self = @This();

    /// Initialize the RNG with a hardcoded seed
    pub fn new() Self {
        return Self{ .state = 0xcafebabedeadbeef };
    }

    /// Initialize the RNG with a provided seed
    pub fn new_with_seed(state: u64) Self {
        std.debug.assert(state != 0); // 0 as a state breaks the rng (will only produce 0)
        return Self{ .state = state };
    }

    /// Generate a new 64 bit random number
    pub fn next(self: *Self) u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return self.state;
    }
};
