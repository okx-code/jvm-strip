const std = @import("std");
const StripError = error{
    BufferTooSmall,
    NotClassFile,
};

const DoubleIndex = struct {
    indexes: [2]u16,
};

const MethodHandle = struct {
    reference_kind: u8,
    reference_index: u16,
};

const SingleIndex = struct {
    index: u16,
};

const Constants = enum(u8) {
    Class = 7,
    Fieldref = 9,
    Methodref = 10,
    InterfaceMethodref = 11,
    String = 8,
    Integer = 3,
    Float = 4,
    Long = 5,
    Double = 6,
    NameAndType = 12,
    Utf8 = 1,
    MethodHandle = 15,
    MethodType = 16,
    Dynamic = 17,
    InvokeDynamic = 18,
    Module = 19,
    Package = 20,
};

const ConstantPool = union(Constants) { Class: SingleIndex, Fieldref: DoubleIndex, Methodref: DoubleIndex, InterfaceMethodref: DoubleIndex, String: SingleIndex, Integer: u32, Float: u32, Long: u64, Double: u64, NameAndType: DoubleIndex, Utf8: []const u8, MethodHandle: MethodHandle, MethodType: SingleIndex, Dynamic: DoubleIndex, InvokeDynamic: DoubleIndex, Module: SingleIndex, Package: SingleIndex };

//    var runtimeVisibleAnnotationAttribute: ?u16 = null;
//    var runtimeVisibleParameterAnnotationsAttribute: ?u16 = null;
// Attributes that contain other attributes, where the index in the constant pool needs to be
// recorded so that they can be rewritten.
// Initialised to 0 which doesn't exist in the constant pool because it starts at 1
const ConstantPoolAttributes = struct {
    constantValue: u16 = 0,
    code: u16 = 0,
    exceptions: u16 = 0,
    innerClasses: u16 = 0,
    enclosingMethod: u16 = 0,
    signature: u16 = 0,
    runtimeVisibleAnnotations: u16 = 0,
    runtimeInvisibleAnnotations: u16 = 0,
    runtimeVisibleParameterAnnotations: u16 = 0,
    runtimeInvisibleParameterAnnotations: u16 = 0,
    annotationDefault: u16 = 0,
    boostrapMethods: u16 = 0,
};

const CLASS_MAGIC: u32 = 0xCAFEBABE;

pub fn strip(in: []const u8, out: []u8, allocator: std.mem.Allocator) !usize {
    var fixedInBuf = std.io.fixedBufferStream(in);
    const inBuf = fixedInBuf.reader();
    var fixedOutBuf = std.io.fixedBufferStream(out);
    const outBuf = fixedOutBuf.writer();

    const magic = inBuf.readIntBig(u32) catch return StripError.NotClassFile;
    if (magic != CLASS_MAGIC) {
        return StripError.NotClassFile;
    }
    outBuf.writeIntBig(u32, magic) catch return StripError.BufferTooSmall;

    const minor = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, minor) catch return StripError.BufferTooSmall;
    const major = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, major) catch return StripError.BufferTooSmall;

    // step 1. copy the constant pool into a dynamic array, remove undesired constants and record their index

    const constantPoolCountPlusOne = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    if (constantPoolCountPlusOne < 1) {
        return StripError.NotClassFile;
    }

    var deletedConstants = try std.ArrayList(u16).initCapacity(allocator, 6);
    defer deletedConstants.deinit();

    var newConstantPool = try allocator.alloc(ConstantPool, constantPoolCountPlusOne - 1);
    defer allocator.free(newConstantPool);

    var attributes = ConstantPoolAttributes{};
    _ = attributes;

    var constantPoolIndex: u16 = 0;
    while (constantPoolIndex < constantPoolCountPlusOne - 1) : (constantPoolIndex += 1) {
        const tag = inBuf.readIntBig(u8) catch return StripError.NotClassFile;
        const newConstantPoolIndex = constantPoolIndex - deletedConstants.items.len;
        if (tag == @enumToInt(Constants.Class)) {
            const nameIndex = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .Class = .{ .index = nameIndex } };
        } else if (tag == @enumToInt(Constants.Fieldref) or tag == @enumToInt(Constants.Methodref) or tag == @enumToInt(Constants.InterfaceMethodref)) {
            const classIndex = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            const nameAndTypeIndex = inBuf.readIntBig(u16) catch return StripError.NotClassFile;

            const ref = DoubleIndex{ .indexes = .{ classIndex, nameAndTypeIndex } };
            newConstantPool[newConstantPoolIndex] = switch (@intToEnum(Constants, tag)) {
                .Fieldref => ConstantPool{ .Fieldref = ref },
                .Methodref => ConstantPool{ .Methodref = ref },
                .InterfaceMethodref => ConstantPool{ .InterfaceMethodref = ref },
                else => unreachable,
            };
        } else if (tag == @enumToInt(Constants.String)) {
            // string_index
            const value = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .String = .{ .index = value } };
        } else if (tag == @enumToInt(Constants.Integer) or tag == @enumToInt(Constants.Float)) {
            // bytes
            const value = inBuf.readIntBig(u32) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = switch (@intToEnum(Constants, tag)) {
                .Integer => ConstantPool{ .Integer = value },
                .Float => ConstantPool{ .Float = value },
                else => unreachable,
            };
        } else if (tag == @enumToInt(Constants.Long) or tag == @enumToInt(Constants.Double)) {
            // bytes
            const value = inBuf.readIntBig(u64) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = switch (@intToEnum(Constants, tag)) {
                .Long => ConstantPool{ .Long = value },
                .Double => ConstantPool{ .Double = value },
                else => unreachable,
            };
        } else if (tag == @enumToInt(Constants.NameAndType)) {
            const name_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            const descriptor_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .NameAndType = .{ .indexes = .{ name_index, descriptor_index } } };
        } else if (tag == @enumToInt(Constants.Utf8)) {
            const length = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            const pos = fixedInBuf.getPos() catch return StripError.NotClassFile;

            if (pos + length >= in.len) return StripError.NotClassFile;
            fixedInBuf.seekTo(pos + length) catch unreachable;
            const bytes = in[pos .. pos + length];
            if (std.mem.eql(u8, bytes, "SourceFile")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else if (std.mem.eql(u8, bytes, "SourceDebugExtension")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else if (std.mem.eql(u8, bytes, "LineNumberTable")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else if (std.mem.eql(u8, bytes, "LocalVariableTable")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else if (std.mem.eql(u8, bytes, "LocalVariableTypeTable")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else if (std.mem.eql(u8, bytes, "Deprecated")) {
                try deletedConstants.append(constantPoolIndex + 1);
            } else {
                newConstantPool[newConstantPoolIndex] = ConstantPool{ .Utf8 = bytes };
                if (std.mem.eql(u8, bytes, "ConstantValue")) {
                    attributes.constantValue = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "Code")) {
                    attributes.code = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "Exceptions")) {
                    attributes.exceptions = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "InnerClasses")) {
                    attributes.innerClasses = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "EnclosingMethod")) {
                    attributes.enclosingMethod = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "Signature")) {
                    attributes.signature = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "RuntimeVisibleAnnotations")) {
                    attributes.runtimeVisibleAnnotations = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "RuntimeInvisibleAnnotations")) {
                    attributes.runtimeInvisibleAnnotations = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "RuntimeVisibleParameterAnnotations")) {
                    attributes.runtimeVisibleParameterAnnotations = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "RuntimeInvisibleParameterAnnotations")) {
                    attributes.runtimeInvisibleParameterAnnotations = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "AnnotationDefault")) {
                    attributes.annotationDefault = constantPoolIndex + 1;
                } else if (std.mem.eql(u8, bytes, "BoostrapMethods")) {
                    attributes.boostrapMethods = constantPoolIndex + 1;
                }
            }
        } else if (tag == @enumToInt(Constants.MethodHandle)) {
            const reference_kind = inBuf.readIntBig(u8) catch return StripError.NotClassFile;
            const reference_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .MethodHandle = .{ .reference_kind = reference_kind, .reference_index = reference_index } };
        } else if (tag == @enumToInt(Constants.MethodType)) {
            const descriptor_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .MethodType = .{ .index = descriptor_index } };
        } else if (tag == @enumToInt(Constants.Dynamic) or tag == @enumToInt(Constants.InvokeDynamic)) {
            const bootstrap_method_attr_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            const name_and_type_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            const doubleIndex = .{ .indexes = .{ bootstrap_method_attr_index, name_and_type_index } };
            newConstantPool[newConstantPoolIndex] = switch (@intToEnum(Constants, tag)) {
                .Dynamic => ConstantPool{ .Dynamic = doubleIndex },
                .InvokeDynamic => ConstantPool{ .InvokeDynamic = doubleIndex },
                else => unreachable,
            };
        } else if (tag == @enumToInt(Constants.Module)) {
            const name_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .Module = .{ .index = name_index } };
        } else if (tag == @enumToInt(Constants.Package)) {
            const name_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
            newConstantPool[newConstantPoolIndex] = ConstantPool{ .Package = .{ .index = name_index } };
        } else {
            return StripError.NotClassFile;
        }
    }

    std.sort.sort(u16, deletedConstants.items, {}, comptime std.sort.desc(u16));

    // step 2. write the new constant pool back out with the indexes adjusted to not include the deletede ones

    const realNewConstantPool = newConstantPool[0 .. newConstantPool.len - deletedConstants.items.len];
    outBuf.writeIntBig(u16, @intCast(u16, realNewConstantPool.len + 1)) catch return StripError.BufferTooSmall;
    for (realNewConstantPool) |*constantPool| {
        outBuf.writeIntBig(u8, @enumToInt(constantPool.*)) catch return StripError.BufferTooSmall;
        switch (constantPool.*) {
            .Class, .MethodType, .Module, .Package, .String => |*singleIndex| {
                // single index
                try updateIndexes(deletedConstants.items, @as(*[1]u16, &singleIndex.index));

                outBuf.writeIntBig(u16, singleIndex.index) catch return StripError.BufferTooSmall;
            },
            .Fieldref, .Methodref, .InterfaceMethodref, .NameAndType, .Dynamic, .InvokeDynamic => |*doubleIndex| {
                // double index
                try updateIndexes(deletedConstants.items, &doubleIndex.indexes);

                outBuf.writeIntBig(u16, doubleIndex.indexes[0]) catch return StripError.BufferTooSmall;
                outBuf.writeIntBig(u16, doubleIndex.indexes[1]) catch return StripError.BufferTooSmall;
            },
            .MethodHandle => |*methodHandle| {
                // one index in a weird place
                try updateIndexes(deletedConstants.items, @as(*[1]u16, &methodHandle.reference_index));

                outBuf.writeIntBig(u8, methodHandle.reference_kind) catch return StripError.BufferTooSmall;
                outBuf.writeIntBig(u16, methodHandle.reference_index) catch return StripError.BufferTooSmall;
            },
            // no index
            .Integer, .Float => |value| {
                outBuf.writeIntBig(u32, value) catch return StripError.BufferTooSmall;
            },
            .Long, .Double => |value| {
                outBuf.writeIntBig(u64, value) catch return StripError.BufferTooSmall;
            },
            .Utf8 => |value| {
                outBuf.writeIntBig(u16, @intCast(u16, value.len)) catch return StripError.BufferTooSmall;
                outBuf.writeAll(value) catch return StripError.BufferTooSmall;
            },
        }
    }

    const access_flags = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, access_flags) catch return StripError.BufferTooSmall;

    const this_class = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, this_class) catch return StripError.BufferTooSmall;

    const super_class = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, super_class) catch return StripError.BufferTooSmall;

    const interfacesCount = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, interfacesCount) catch return StripError.BufferTooSmall;

    // step 3. rewrite usages of the constant pool on the field, methods, class, and interface

    var interfacesIndex: u16 = 0;
    while (interfacesIndex < interfacesCount) : (interfacesIndex += 1) {
        var interface = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants.items, @as(*[1]u16, &interface));
        outBuf.writeIntBig(u16, interface) catch return StripError.BufferTooSmall;
    }

    const fieldCount = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, fieldCount) catch return StripError.BufferTooSmall;

    var fieldIndex: u16 = 0;
    while (fieldIndex < fieldCount) : (fieldIndex += 1) {
        const field_access_flags = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        outBuf.writeIntBig(u16, field_access_flags) catch return StripError.BufferTooSmall;
        var name_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants.items, @as(*[1]u16, &name_index));
        outBuf.writeIntBig(u16, name_index) catch return StripError.BufferTooSmall;
        var descriptor_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants.items, @as(*[1]u16, &descriptor_index));
        outBuf.writeIntBig(u16, descriptor_index) catch return StripError.BufferTooSmall;

        try processAttributes(deletedConstants.items, &fixedInBuf, &fixedOutBuf, attributes);
    }

    const methodCount = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
    outBuf.writeIntBig(u16, methodCount) catch return StripError.BufferTooSmall;

    var methodIndex: u16 = 0;
    while (methodIndex < methodCount) : (methodIndex += 1) {
        const method_access_flags = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        outBuf.writeIntBig(u16, method_access_flags) catch return StripError.BufferTooSmall;
        var name_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants.items, @as(*[1]u16, &name_index));
        outBuf.writeIntBig(u16, name_index) catch return StripError.BufferTooSmall;
        var descriptor_index = inBuf.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants.items, @as(*[1]u16, &descriptor_index));
        outBuf.writeIntBig(u16, descriptor_index) catch return StripError.BufferTooSmall;

        try processAttributes(deletedConstants.items, &fixedInBuf, &fixedOutBuf, attributes);
    }

    try processAttributes(deletedConstants.items, &fixedInBuf, &fixedOutBuf, attributes);

    return fixedOutBuf.pos;
}

fn processAttributes(deletedConstants: []const u16, inBuf: *std.io.FixedBufferStream([]const u8), outBuf: *std.io.FixedBufferStream([]u8), attributes: ConstantPoolAttributes) StripError!void {
    const reader = inBuf.reader();
    const writer = outBuf.writer();

    const attributeCountWritePos = outBuf.getPos() catch return StripError.BufferTooSmall;
    outBuf.seekBy(2) catch StripError.BufferTooSmall; // write the length later

    const attributesCount = reader.readIntBig(u16) catch return StripError.NotClassFile;
    var attributesKeptCount: u16 = 0;
    var attributeIndex: u16 = 0;
    while (attributeIndex < attributesCount) : (attributeIndex += 1) {
        var attribute_name_index = reader.readIntBig(u16) catch return StripError.NotClassFile;
        const attribute_length = reader.readIntBig(u32) catch return StripError.NotClassFile;
        if (inBuf.pos + attribute_length > inBuf.getEndPos() catch unreachable) {
            return StripError.BufferTooSmall;
        }

        const beginPos = inBuf.pos;
        if (!contains(deletedConstants, attribute_name_index)) {
            const attribute = attribute_name_index;
            try updateIndexes(deletedConstants, @as(*[1]u16, &attribute_name_index));
            writer.writeIntBig(u16, attribute_name_index) catch return StripError.BufferTooSmall;
            const attributeLengthPosition = outBuf.pos;
            writer.writeIntBig(u32, attribute_length) catch return StripError.BufferTooSmall;

            // handle recursive attributes
            if (attributes.constantValue == attribute) {
                var index = reader.readIntBig(u16) catch return StripError.NotClassFile;
                try updateIndexes(deletedConstants, @as(*[1]u16, &index));
                writer.writeIntBig(u16, index) catch return StripError.BufferTooSmall;
            } else if (attributes.code == attribute) {
                const codePosition = outBuf.pos;

                const max_stack = reader.readIntBig(u16) catch return StripError.NotClassFile;
                writer.writeIntBig(u16, max_stack) catch return StripError.BufferTooSmall;

                const max_locals = reader.readIntBig(u16) catch return StripError.NotClassFile;
                writer.writeIntBig(u16, max_locals) catch return StripError.BufferTooSmall;

                const code_length = reader.readIntBig(u32) catch return StripError.NotClassFile;
                writer.writeIntBig(u32, code_length) catch return StripError.BufferTooSmall;

                if (inBuf.pos + code_length > inBuf.getEndPos() catch unreachable) {
                    return StripError.BufferTooSmall;
                }
                writer.writeAll(inBuf.buffer[inBuf.pos .. inBuf.pos + code_length]) catch return StripError.BufferTooSmall;
                inBuf.seekTo(inBuf.pos + code_length) catch unreachable;

                const exception_table_length = reader.readIntBig(u16) catch return StripError.NotClassFile;
                writer.writeIntBig(u16, exception_table_length) catch return StripError.BufferTooSmall;

                const exception_table_length_bytes = exception_table_length * 8; // todo adjust constant pool catch_type here
                if (inBuf.pos + exception_table_length_bytes > inBuf.getEndPos() catch unreachable) {
                    return StripError.BufferTooSmall;
                }
                writer.writeAll(inBuf.buffer[inBuf.pos .. inBuf.pos + exception_table_length_bytes]) catch return StripError.BufferTooSmall;
                inBuf.seekTo(inBuf.pos + exception_table_length_bytes) catch unreachable;

                try processAttributes(deletedConstants, inBuf, outBuf, attributes);

                const newAttributeLength = @intCast(u32, outBuf.pos - codePosition);

                const outBufPos = outBuf.pos;
                outBuf.seekTo(attributeLengthPosition) catch unreachable;
                // override length
                writer.writeIntBig(u32, newAttributeLength) catch unreachable;
                outBuf.seekTo(outBufPos) catch unreachable;
            } else if (attributes.exceptions == attribute) {
                const exceptions = reader.readIntBig(u16) catch return StripError.NotClassFile;
                writer.writeIntBig(u16, exceptions) catch return StripError.BufferTooSmall;
                var exceptionIndex: u16 = 0;
                while (exceptionIndex < exceptions) : (exceptionIndex += 1) {
                    var exceptionConstant = reader.readIntBig(u16) catch return StripError.NotClassFile;
                    try updateIndexes(deletedConstants, @as(*[1]u16, &exceptionConstant));
                    writer.writeIntBig(u16, exceptionConstant) catch return StripError.BufferTooSmall;
                }
            } else if (attributes.runtimeVisibleAnnotations == attribute or attributes.runtimeInvisibleAnnotations == attribute) {
                const annotations = reader.readIntBig(u16) catch return StripError.NotClassFile;
                writer.writeIntBig(u16, annotations) catch return StripError.BufferTooSmall;
                var annotationIndex: u16 = 0;
                while (annotationIndex < annotations) : (annotationIndex += 1) {
                    try rewriteAnnotation(deletedConstants, inBuf, outBuf);
                }
            } else {
                writer.writeAll(inBuf.buffer[inBuf.pos .. inBuf.pos + attribute_length]) catch return StripError.BufferTooSmall;
            }

            attributesKeptCount += 1;
        } else {
            // deleted
        }
        inBuf.seekTo(beginPos + attribute_length) catch unreachable;
    }

    const currentPosition = outBuf.getPos() catch unreachable;
    outBuf.seekTo(attributeCountWritePos) catch unreachable;
    writer.writeIntBig(u16, attributesKeptCount) catch unreachable;
    outBuf.seekTo(currentPosition) catch unreachable;
}

fn rewriteAnnotation(deletedConstants: []const u16, inBuf: *std.io.FixedBufferStream([]const u8), outBuf: *std.io.FixedBufferStream([]u8)) StripError!void {
    const reader = inBuf.reader();
    const writer = outBuf.writer();

    var type_index = reader.readIntBig(u16) catch return StripError.NotClassFile;
    try updateIndexes(deletedConstants, @as(*[1]u16, &type_index));
    writer.writeIntBig(u16, type_index) catch return StripError.BufferTooSmall;

    const num_element_value_pairs = reader.readIntBig(u16) catch return StripError.NotClassFile;
    writer.writeIntBig(u16, num_element_value_pairs) catch return StripError.BufferTooSmall;
    var pairIndex: u16 = 0;
    while (num_element_value_pairs < pairIndex) : (pairIndex += 1) {
        var element_name_index = reader.readIntBig(u16) catch return StripError.NotClassFile;
        try updateIndexes(deletedConstants, @as(*[1]u16, &element_name_index));
        writer.writeIntBig(u16, element_name_index) catch return StripError.BufferTooSmall;

        try rewriteElementValue(deletedConstants, inBuf, outBuf);
    }
}

fn rewriteElementValue(deletedConstants: []const u16, inBuf: *std.io.FixedBufferStream([]const u8), outBuf: *std.io.FixedBufferStream([]u8)) StripError!void {
    const reader = inBuf.reader();
    const writer = outBuf.writer();
    const tag = reader.readIntBig(u8) catch return StripError.NotClassFile;
    writer.writeIntBig(u8, tag) catch return StripError.BufferTooSmall;
    switch (tag) {
        'B', 'C', 'D', 'F', 'I', 'J', 'S', 'Z', 's', 'c' => {
            var index = reader.readIntBig(u16) catch return StripError.NotClassFile;
            try updateIndexes(deletedConstants, @as(*[1]u16, &index));
            writer.writeIntBig(u16, index) catch return StripError.BufferTooSmall;
        },
        'e' => {
            var type_name_index = reader.readIntBig(u16) catch return StripError.NotClassFile;
            var const_name_index = reader.readIntBig(u16) catch return StripError.NotClassFile;
            try updateIndexes(deletedConstants, @as(*[1]u16, &type_name_index));
            try updateIndexes(deletedConstants, @as(*[1]u16, &const_name_index));
            writer.writeIntBig(u16, type_name_index) catch return StripError.BufferTooSmall;
            writer.writeIntBig(u16, const_name_index) catch return StripError.BufferTooSmall;
        },
        '@' => {
            std.debug.panic("todo", .{});
        },
        '[' => {
            const num_values = reader.readIntBig(u16) catch return StripError.NotClassFile;
            var valueIndex: u16 = 0;
            while (valueIndex < num_values) : (valueIndex += 1) {
                try rewriteElementValue(deletedConstants, inBuf, outBuf);
            }
        },
        else => {
            return StripError.NotClassFile;
        },
    }
}

fn contains(deletedConstants: []const u16, search: u16) bool {
    for (deletedConstants) |deletedConstant| {
        if (deletedConstant == search) {
            return true;
        }
    }
    return false;
}

fn updateIndexes(deletedConstants: []const u16, indexes: []u16) !void {
    for (deletedConstants) |deletedConstant| {
        for (indexes) |*index| {
            if (index.* >= deletedConstant) {
                index.* -= 1;
            }
        }
    }
}
