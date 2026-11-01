
// Luau bindings for Odin (Up to date with 0.745)
// Derived from @MineBill/odin-luau (GitHub)
// MIT Licensed | @AnotherSubatomo/odin-luau-bindings (Github)

// Based on: https://github.com/luau-lang/luau/blob/master/Compiler/include/luacode.h

package luau
import "core:c"

when ODIN_OS == .Windows {
	foreign import LuauCompiler {
		"./target/lib/Luau.Compiler.lib",
		"./target/lib/Luau.AST.lib",
		"./target/lib/Luau.CLI.lib.lib",
	}
} else {
	foreign import LuauCompiler {
		"./target/lib/Luau.Compiler.a",
		"./target/lib/Luau.AST.a",
		"./target/lib/Luau.CLI.lib.a",
	}
}

LibraryMemberTypeCallback     :: #type proc "c" (library: cstring, member: cstring) -> c.int
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

@(link_prefix="luau_")
foreign LuauCompiler {
	// compile source to bytecode; when source compilation fails, the resulting bytecode contains the encoded error. use free() to destroy
	compile :: proc(source: cstring, size: c.size_t, options: ^CompileOptions, out_size: ^c.size_t) -> cstring ---
}

// Required for whatever reason, do not delete!
@(export, link_name="_fltused", private="file")
_fltused: u32 = 0x9875
