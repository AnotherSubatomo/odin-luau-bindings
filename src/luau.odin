
// Luau bindings for Odin (Up to date with 0.745)
// Derived from @MineBill/odin-luau (GitHub)
// MIT Licensed | @AnotherSubatomo/odin-luau-bindings (Github)

// Based on: https://github.com/luau-lang/luau/blob/master/Compiler/include/luacode.h

package luau
import "core:c"

when ODIN_OS == .Windows {
	foreign import LuauCompiler {
		"./target/lib/luau.Compiler.lib",
		"./target/lib/luau.Ast.lib",
		"./target/lib/Luau.Bytecode.lib",
		"./target/lib/Luau.VM.lib",
		"./target/lib/Luau.Common.lib",
	}
} else {
	foreign import LuauCompiler {
		"./target/lib/luau.Compiler.a",
		"./target/lib/luau.Ast.a",
		"./target/lib/Luau.Bytecode.a",
		"./target/lib/Luau.VM.a",
		"./target/lib/Luau.Common.a",
	}
}

// return a type identifier for a global library member
// values are defined by 'enum LuauBytecodeType' in Bytecode.h
LibraryMemberTypeCallback     :: #type proc "c" (library: cstring, member: cstring) -> c.int

// setup a value of a constant for a global library member
// use luau_set_compile_constant_*** set of functions for values
LibraryMemberConstantCallback :: #type proc "c" (library: cstring, member: cstring, constant: rawptr)

CompileOptions :: struct {
	// 0 - no optimization
	// 1 - baseline optimization level that doesn't prevent debuggability
	// 2 - includes optimizations that harm debuggability such as inlining
	optimization_level: c.int, // default=1

	// 0 - no debugging support
	// 1 - line info & function names only; sufficient for backtraces
	// 2 - full debug info with local & upvalue names; necessary for debugger
	debug_level: c.int, // default=1

	// type information is used to guide native code generation decisions
	// information includes testable types for function arguments, locals, upvalues and some temporaries
	// 0 - generate for native modules
	// 1 - generate for all modules
	type_info_level: c.int, // default=0

	// 0 - no code coverage support
	// 1 - statement coverage
	// 2 - statement and expression coverage (verbose)
	coverage_level: c.int, // default=0

	// alternative global builtin to construct vectors, in addition to default builtin 'vector.create'
	vector_lib: cstring,
	vector_ctor: cstring,

	// alternative vector type name for type tables, in addition to default type 'vector'
	vector_type: cstring,

	// 0 - 32-bit float vector components
    // 1 - 64-bit double vector components
    vector_precision: c.int, // default=0

	// null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
	mutable_globals: [^]cstring,

	// null-terminated array of userdata types that will be included in the type information
	userdata_types: [^]cstring,

	// null-terminated array of globals which act as libraries and have members with known type and/or constant value
	libraries_with_known_members: [^]cstring,
	library_member_type_cb: LibraryMemberTypeCallback,
	library_member_constant_cb: LibraryMemberConstantCallback,

	// null-terminated array of library functions that should not be compiled into a built-in fastcall ("name" "lib.name")
	disabled_builtins: [^]cstring,
}

@(link_prefix="luau_", default_calling_convention="c")
foreign LuauCompiler {
	// compile source to bytecode; when source compilation fails, the resulting bytecode contains the encoded error. use free() to destroy
	compile :: proc(source: cstring, size: c.size_t, options: ^CompileOptions, out_size: ^c.size_t) -> cstring ---

	// when libraryMemberConstantCb is called, these methods can be used to set a value of the opaque lua_CompileConstant struct
	// vector component 'w' is not visible to VM runtime configured with LUA_VECTOR_SIZE == 3, but can affect constant folding during compilation
	// string storage must outlive the invocation of 'luau_compile' which used the callback
	luau_set_compile_constant_nil :: proc(constant: rawptr) ---
	luau_set_compile_constant_boolean :: proc(constant: rawptr, b: c.int) ---
	luau_set_compile_constant_number :: proc(constant: rawptr, n: c.double) ---
	luau_set_compile_constant_integer64 :: proc(constant: rawptr, l: c.int64_t) ---
	luau_set_compile_constant_vector :: proc(constant: rawptr, x, y, z, w: c.float) ---
	luau_set_compile_constant_vectord :: proc(constant: rawptr, x, y, z, w: c.double) ---
	luau_set_compile_constant_string :: proc(constant: rawptr, s: cstring, l: c.size_t) ---
}

// Required for whatever reason, do not delete!
@(export, link_name="_fltused", private="file")
_fltused: u32 = 0x9875
