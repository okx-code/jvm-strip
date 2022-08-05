const std = @import("std");
const strip = @import("strip.zig");

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const gpa = general_purpose_allocator.allocator();

    var args = try std.process.argsAlloc(gpa);
    defer gpa.free(args);

    if (args.len < 2) {
        std.debug.print("usage: jvm-strip <file>\n", .{});
        return;
    }

    const readFile = try std.fs.cwd().openFile(args[1], .{});
    defer readFile.close();

    const inBytes = try readFile.readToEndAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(inBytes);

    var outBytes = try gpa.alloc(u8, inBytes.len);
    defer gpa.free(outBytes);

    const size = try strip.strip(inBytes, outBytes, gpa);
    std.debug.print("reduced {d} to {d} bytes\n", .{ inBytes.len, size });
    const file = try std.fs.cwd().createFile("output.class", .{});
    defer file.close();

    try file.writeAll(outBytes[0..size]);
}
