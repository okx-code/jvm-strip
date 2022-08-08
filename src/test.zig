const std = @import("std");
const strip = @import("strip.zig");

const gpa = std.testing.allocator;

test "lines are stripped" {
    // The TestLineStrip class tests if the line numbers have been stripped by checking
    // the stack trace.

    const TestLineStrip_name_java = "TestLineStrip";
    const TestLineStrip_name_file = TestLineStrip_name_java ++ ".class";
    const TestLineStrip_class = @embedFile(TestLineStrip_name_file);

    var TestLineStrip_class_outputBuffer: [TestLineStrip_class.len]u8 = undefined;

    const size = try strip.strip(TestLineStrip_class, &TestLineStrip_class_outputBuffer, gpa);

    var tmpDir = std.testing.tmpDir(.{});
    defer tmpDir.cleanup();
    {
        const file = try tmpDir.dir.createFile(TestLineStrip_name_file, .{});
        defer file.close();
        try file.writeAll(TestLineStrip_class_outputBuffer[0..size]);
    }
    const path = try tmpDir.parent_dir.realpathAlloc(gpa, &tmpDir.sub_path);
    defer gpa.free(path);

    var process = std.ChildProcess.init(&.{ "java", TestLineStrip_name_java }, gpa);
    process.cwd = path;

    try process.spawn();
    const result = try process.wait();
    try std.testing.expectEqual(std.ChildProcess.Term{ .Exited = 0 }, result);
}
