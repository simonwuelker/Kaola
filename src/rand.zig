pub const Rand64 = struct {
    state: u64,

    pub fn new() Rand64 {
        return Rand64 { .state = 0xcafebabedeadbeef };
    }

    pub fn next(self: *Rand64) u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return self.state;
    }
};
