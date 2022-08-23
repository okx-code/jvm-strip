const std = @import("std");
const strip = @import("strip.zig");

const gpa = std.testing.allocator;

const TestLineStrip_name_java = "TestLineStrip";
const TestLineStrip_name_file = TestLineStrip_name_java ++ ".class";
const TestLineStrip_class = @embedFile(TestLineStrip_name_file);

test "lines are stripped" {
    // The TestLineStrip class tests if the line numbers have been stripped by checking
    // the stack trace.

    var TestLineStrip_class_outputBuffer: [TestLineStrip_class.len]u8 = undefined;

    const size = try strip.strip(TestLineStrip_class, &TestLineStrip_class_outputBuffer, gpa);

    var tmpDir = std.testing.tmpDir(.{});
    defer tmpDir.cleanup();
    {
        const file = try tmpDir.dir.createFile(TestLineStrip_name_file, .{});
        defer file.close();
        try file.writeAll(TestLineStrip_class_outputBuffer[0..size]);
    }

    // java will only run if it is in the same directory as the class file
    const path = try tmpDir.parent_dir.realpathAlloc(gpa, &tmpDir.sub_path);
    defer gpa.free(path);

    // Zig 0.9
    var process = try std.ChildProcess.init(&.{ "java", TestLineStrip_name_java }, gpa);
    defer process.deinit();

    // Zig 0.10
    //var process = std.ChildProcess.init(&.{ "java", TestLineStrip_name_java }, gpa);

    process.cwd = path;

    try process.spawn();
    const result = try process.wait();
    try std.testing.expectEqual(std.ChildProcess.Term{ .Exited = 0 }, result);
}

test "double strip" {
    // Ensures that stripping a class file that was already stripped does not change anything
    var TestLineStrip_class_singleStripBuffer: [TestLineStrip_class.len]u8 = undefined;
    var TestLineStrip_class_doubleStripBuffer: [TestLineStrip_class.len]u8 = undefined;

    const singleStripSize = try strip.strip(TestLineStrip_class, &TestLineStrip_class_singleStripBuffer, gpa);
    const doubleStripSize = try strip.strip(&TestLineStrip_class_singleStripBuffer, &TestLineStrip_class_doubleStripBuffer, gpa);

    try std.testing.expectEqualSlices(u8, TestLineStrip_class_singleStripBuffer[0..singleStripSize], TestLineStrip_class_doubleStripBuffer[0..doubleStripSize]);
}
