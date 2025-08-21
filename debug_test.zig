const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Let's try to see what type we're actually getting
    const MyList = std.ArrayList(u8);
    @compileLog(@typeName(MyList));
    
    // This should work according to the standard library examples
    var list = MyList.init(allocator);
    defer list.deinit();

    std.debug.print("Success!\n", .{});
}