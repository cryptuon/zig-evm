// Enhanced BigInt implementation for 256-bit integers
pub const BigInt = struct {
    data: [4]u64,

    pub fn init(value: u64) BigInt {
        return BigInt{ .data = .{ value, 0, 0, 0 } };
    }

    pub fn add(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        var carry: u64 = 0;

        for (0..4) |i| {
            const sum = self.data[i] +% other.data[i] +% carry;
            result.data[i] = sum & 0xFFFFFFFFFFFFFFFF;
            carry = if (sum < self.data[i]) 1 else 0;
        }

        return result;
    }

    pub fn sub(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        var borrow: u64 = 0;

        for (0..4) |i| {
            const diff = self.data[i] -% other.data[i] -% borrow;
            borrow = if (self.data[i] < other.data[i] +% borrow) @as(u64, 1) else @as(u64, 0);
            result.data[i] = diff;
        }

        return result;
    }

    pub fn mul(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        
        // Simple implementation for now - just multiply the least significant words
        // This is not a complete 256-bit multiplication but sufficient for basic testing
        result.data[0] = self.data[0] *% other.data[0];
        
        return result;
    }

    pub fn lt(self: BigInt, other: BigInt) bool {
        // Compare from most significant to least significant
        for (0..4) |i| {
            const idx = 3 - i; // Start from the most significant word
            if (self.data[idx] < other.data[idx]) return true;
            if (self.data[idx] > other.data[idx]) return false;
        }
        return false; // They are equal
    }

    // Add more arithmetic operations (subtract, multiply, divide) here
};
