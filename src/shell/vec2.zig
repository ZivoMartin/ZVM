pub const Vec2 = struct {
    x: i32,
    y: i32,

    pub fn new(x: i32, y: i32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }

    pub fn zero() Vec2 {
        return Vec2.new(0, 0);
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2.new(self.x + other.x, self.y + other.y);
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return Vec2.new(self.x - other.x, self.y - other.y);
    }

    pub fn mul(self: Vec2, other: Vec2) Vec2 {
        return Vec2.new(self.x * other.x, self.y * other.y);
    }
};
