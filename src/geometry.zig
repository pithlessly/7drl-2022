const std = @import("std");

pub const Vec2 = struct {
    x: i16,
    y: i16,

    pub fn new(x: i16, y: i16) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn eq(self: Vec2, other: Vec2) bool {
        return std.meta.eql(self, other);
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn dist(self: Vec2, other: Vec2) u32 {
        const dx = @as(i32, self.x) - @as(i32, other.x);
        const dy = @as(i32, self.y) - @as(i32, other.y);
        return @intCast(u32, dx * dx) + @intCast(u32, dy * dy);
    }

    pub fn serialize(self: Vec2) u32 {
        return @bitCast(u32, self);
    }
};

pub const Slope = struct {
    numer: u16,
    denom: u16,

    fn gcd(a: u16, b: u16) u16 {
        var aa = a;
        var bb = b;
        while (bb > 0) {
            const tmp = aa % bb;
            aa = bb;
            bb = tmp;
        }
        return aa;
    }

    pub fn new(numer: u16, denom: u16) Slope {
        // TODO: determine if computing gcd is necessary here
        const gcd_ = gcd(numer, denom);
        return .{ .numer = @divExact(numer, gcd_), .denom = @divExact(denom, gcd_) };
    }

    fn delta(self: Slope, other: Slope) i64 {
        const lprod: i64 = std.math.mulWide(u16, self.numer, other.denom);
        const rprod: i64 = std.math.mulWide(u16, other.numer, self.denom);
        return lprod - rprod;
    }

    pub fn eq(self: Slope, other: Slope) bool {
        return self.delta(other) == 0;
    }

    pub fn gt(self: Slope, other: Slope) bool {
        return self.delta(other) > 0;
    }

    pub fn ge(self: Slope, other: Slope) bool {
        return self.delta(other) >= 0;
    }
};

test "compilation" {
    std.testing.refAllDecls(Vec2);
    std.testing.refAllDecls(Slope);
}
