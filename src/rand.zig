/// Xorshift64 Random Number Generator
pub const Rand64 = struct {
    state: u64,

    /// Initialize the RNG with a hardcoded seed
    pub fn new() Rand64 {
        return Rand64{ .state = 0xcafebabedeadbeef };
    }

    /// Generate a new 64 bit random number
    pub fn next(self: *Rand64) u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return self.state;
    }
};
