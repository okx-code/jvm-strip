## jvm-strip

Tool to remove optional debugging attributes from class files to reduce class size. This process can reduce class size by 25% uncompressed.

Deletes the following attributes from class files: 
- SourceFile - the name of the file of this class when it was compiled (usually ends with .java)
- SourceDebugExtension - arbitrary debug data, mostly unused
- LineNumberTable - line numbers of code, used for stack traces
- LocalVariableTable - names and types of variables, used for NullPointerException
- LocalVariableTypeTable - ditto, for generic variables
- Deprecated - used as a hint to a compiler when this class is linked, not the same as the @Deprecated annotation

Compile with `zig build -Drelease-fast=true`, the binary is placed in `zig-out/bin/jvm-strip`

Usage: `jvm-strip <file>` where `<file>` is the .class file you want to be stripped. The output is placed in `output.class`.
