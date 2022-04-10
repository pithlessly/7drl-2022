//! An implementation of Adam Milazzo's algorithm for tile visibility, which can be found at
//! <http://www.adammil.net/blog/v125_Roguelike_Vision_Algorithms.html>.

const std = @import("std");

const geometry = @import("geometry.zig");
const Vec2 = geometry.Vec2;
const Slope = geometry.Slope;

// The algorithm works by dividing up the world around the origin into eight triangular
// regions. Each region is bounded by one orthogonal line and one diagonal line, and
// coordinates are transformed such that vision computation in each octave can treat the
// orthogonal bounding line as 'y = 0' and and the diagonal bounding line is 'y = x'.
const Octant = u3;
fn adjustForOctant(origin: Vec2, o: Octant, p: Vec2) Vec2 {
    return origin.add(switch (o) {
        0 => Vec2.new(p.x, -p.y),
        1 => Vec2.new(p.y, -p.x),
        2 => Vec2.new(-p.y, -p.x),
        3 => Vec2.new(-p.x, -p.y),
        4 => Vec2.new(-p.x, p.y),
        5 => Vec2.new(-p.y, p.x),
        6 => Vec2.new(p.y, p.x),
        7 => Vec2.new(p.x, p.y),
    });
}

// World should provide the following API:
//    fn isOpaque(self, Vec2) bool       whether a given point is solid
//    fn magnitude(Vec2) u32             distance metric to origin
//    fn markVisible(self, Vec2) !void   mark a given point as visible
pub fn Visibility(comptime World: type, comptime Error: type) type {
    return struct {
        world: World,
        origin: Vec2,
        max_distance: u32,

        const Self = @This();

        fn isOpaque(self: *Self, o: Octant, p: Vec2) bool {
            return self.world.isOpaque(adjustForOctant(self.origin, o, p));
        }

        fn markVisible(self: *Self, o: Octant, p: Vec2) Error!void {
            return self.world.markVisible(adjustForOctant(self.origin, o, p));
        }

        fn vec(x: i32, y: i32) Vec2 {
            return Vec2.new(@intCast(i16, x), @intCast(i16, y));
        }

        fn slope(x: i32, y: i32) Slope {
            return Slope.new(@intCast(u16, x), @intCast(u16, y));
        }

        /// Recursively add visible points in the sector bounded by the lines given by
        /// `top` and `bottom` and whose relative x coordinate is at least `min_x`.
        fn computeSector(
            self: *Self,
            oct: Octant,
            param_top: Slope,
            param_bottom: Slope,
            min_x: i32,
            max_x: i32,
        ) Error!void {
            var top = param_top;
            var bottom = param_bottom;
            var x = min_x;
            while (x < max_x) : (x += 1) {
                const column_top_y = if (top.numer == top.denom)
                    x
                else blk: {
                    const n = top.numer;
                    const d = top.denom;
                    var top_y = @intCast(i32, ((2 * @intCast(u32, x) - 1) * n + d) / (2 * d));
                    if (self.isOpaque(oct, vec(x, top_y))) {
                        if (top.ge(slope(2 * top_y + 1, 2 * x)) and
                            !self.isOpaque(oct, vec(x, top_y + 1)))
                            top_y += 1;
                    } else {
                        var ax = 2 * x;
                        if (self.isOpaque(oct, vec(x + 1, top_y + 1)))
                            ax += 1;
                        if (top.gt(slope(top_y + 1, ax)))
                            top_y += 1;
                    }
                    break :blk top_y;
                };
                const column_bottom_y = if (bottom.numer == 0)
                    0
                else blk: {
                    const n = bottom.numer;
                    const d = bottom.denom;
                    var bottom_y = @intCast(i32, ((2 * @intCast(u32, x) - 1) * n + d) / (2 * d));
                    if (bottom.ge(slope(2 * bottom_y + 1, 2 * x)) and
                        self.isOpaque(oct, vec(x, bottom_y)) and
                        !self.isOpaque(oct, vec(x, bottom_y + 1)))
                        bottom_y += 1;
                    break :blk bottom_y;
                };
                var last_cell_was_opaque: ?bool = null;
                var y = column_top_y;
                while (y >= column_bottom_y) : (y -= 1) {
                    const cell_loc = vec(x, y);
                    if (World.magnitude(cell_loc) > self.max_distance) continue;
                    {
                        const cell_slope = slope(y, x);
                        // check if this cell should be visible
                        if ((y != column_top_y or top.ge(cell_slope)) and
                            (y != column_bottom_y or cell_slope.ge(bottom)))
                            try self.markVisible(oct, cell_loc);
                    }

                    const cell_is_opaque = self.isOpaque(oct, cell_loc);
                    defer last_cell_was_opaque = cell_is_opaque;
                    if (last_cell_was_opaque != !cell_is_opaque) continue;

                    const mid_slope = slope(2 * y + 1, 2 * x);
                    if (cell_is_opaque)
                        if (top.gt(mid_slope))
                            if (y == column_bottom_y) {
                                bottom = mid_slope;
                                break;
                            } else try self.computeSector(oct, top, mid_slope, x + 1, max_x)
                        else if (y == column_bottom_y)
                            return
                        else {}
                    else if (bottom.ge(mid_slope))
                        return
                    else
                        top = mid_slope;
                }
                if (last_cell_was_opaque != false)
                    break;
            }
        }

        pub fn compute(self: *Self) Error!void {
            try self.world.markVisible(self.origin);
            const max_x = @intCast(i32, self.max_distance);
            var oct: Octant = 0;
            while (true) {
                try self.computeSector(oct, Slope.new(1, 1), Slope.new(0, 1), 1, max_x);
                if (oct == 7) break else oct += 1;
            }
        }
    };
}

test "compilation" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Visibility(struct {
        const Self = @This();
        fn isOpaque(self: Self, at: Vec2) bool {
            _ = self;
            _ = at;
            @panic("unimplemented");
        }
        fn magnitude(at: Vec2) u32 {
            _ = at;
            @panic("unimplemented");
        }
        fn markVisible(self: Self, at: Vec2) void {
            _ = self;
            _ = at;
            @panic("unimplemented");
        }
    }));
}
