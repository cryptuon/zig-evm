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
            const sum = self.data[i] + other.data[i] + carry;
            result.data[i] = sum & 0xFFFFFFFFFFFFFFFF;
            carry = sum >> 64;
        }

        return result;
    }

    // Add more arithmetic operations (subtract, multiply, divide) here
};
