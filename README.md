## jvm-strip

Tool to remove optional debugging attributes from class files to reduce class size. This process can reduce class size by 25% uncompressed.

Deletes the following attributes from class files: 
- SourceFile
- SourceDebugExtension
- LineNumberTable
- LocalVariableTable
- LocalVariableTypeTable
- Deprecated

Compile with `zig build -Drelease-fast=true`, the binary is placed in `zig-out/bin/jvm-strip`

Usage: `jvm-strip <file>` where `<file>` is the .class file you want to be stripped. The output is placed in `output.class`.
