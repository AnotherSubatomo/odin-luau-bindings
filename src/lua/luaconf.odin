// Based on: https://github.com/luau-lang/luau/blob/master/VM/include/luaconf.h

package luau_vm
import "core:c"

// ==== ATTENTION! ====
// This file reflects the configuration that was used to compile the libraries.
// It is __NOT__ meant to configure Luau, it just tells you how it __WAS__ configured.
// Different options and settings in the CMake file, can change the definitions
// in luaconf.h, in which case this file must be updated to reflect them.
// ==== ATTENTION! ====

// Can be used to reconfigure internal error handling to use longjmp instead of C++ EH
USE_LONGJMP :: 1

// IDSIZE gives the maximum size for the description of the source
IDSIZE :: 256

// MINSTACK is the guaranteed number of Lua stack slots available to a C function
MINSTACK :: 20

// MAXCSTACK limits the number of Lua stack slots that a C function can use
MAXCSTACK :: 8000

// MAXCALLS limits the number of nested calls
MAXCALLS :: 20000

// MAXCCALLS is the maximum depth for nested C calls; this limit depends on native stack size
MAXCCALLS :: 200

// buffer size used for on-stack string operations; this limit depends on native stack size
BUFFERSIZE :: 512

// number of valid Lua userdata tags
UTAG_LIMIT :: 128

// number of valid Lua lightuserdata tags
LUTAG_LIMIT :: 128

// upper bound for number of size classes used by page allocator
SIZECLASSES :: 40

// available number of separate memory categories
MEMORY_CATEGORIES :: 256

// extra storage for execution callbacks in global state
EXECUTION_CALLBACK_STORAGE :: 512

// minimum size for the string table (must be power of :: 2)
MINSTRTABSIZE :: 32

// maximum number of captures supported by pattern matching
MAXCAPTURES :: 32

LUAU_VECTOR_DOUBLE :: #config(LUAU_VECTOR_DOUBLE, false)
LUAU_VECTOR_FOUR_WIDE :: #config(LUAU_VECTOR_FOUR_WIDE, false)

when LUAU_VECTOR_FOUR_WIDE {
	VECTOR_SIZE :: 4
} else {
	VECTOR_SIZE :: 3
}

when LUAU_VECTOR_DOUBLE {
	VECTOR_TYPE :: c.double
} else {
	VECTOR_TYPE :: c.float
}
