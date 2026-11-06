// Based on: https://github.com/luau-lang/luau/blob/master/Require/include/Luau/Require.h

package luau_require
import "core:c"
import "../lua"

when ODIN_OS == .Windows {
	foreign import LuauRequire {
		"../target/lib/Luau.Require.lib",
	}
} else {
	foreign import LuauRequire {
		"../target/lib/Luau.Require.a",
	}
}

State :: lua.State

NavigateResult :: enum c.int {
	SUCCESS,
	AMBIGUOUS,
	NOT_FOUND,
}

// Functions returning .SUCCESS are expected to set their `size_out` argument
// to the number of bytes written to the buffer. If .BUFFER_TOO_SMALL is
// returned, `size_out` should be set to the required buffer size.
WriteResult :: enum c.int {
	SUCCESS,
	BUFFER_TOO_SMALL,
	FAILURE,
}

// Represents whether a configuration file is present, and if so, its syntax.
ConfigStatus :: enum c.int {
	ABSENT,
	AMBIGUOUS, // Signals the presence of multiple configuration files.
	PRESENT_JSON,
	PRESENT_LUAU,
}

Configuration :: struct {
	// Returns whether requires are permitted from the given chunkname.
	is_require_allowed: proc "c" (L: ^State, ctx: rawptr, requirer_chunkname: cstring) -> c.bool,

	// Resets the internal state to point at the requirer module.
	reset: proc "c" (L: ^State, ctx: rawptr, requirer_chunkname: cstring) -> NavigateResult,

	// Resets the internal state to point at an aliased module, given its exact
	// path from a configuration file. This function is only called when an
	// alias's path cannot be resolved relative to its configuration file.
	jump_to_alias: proc "c" (L: ^State, ctx: rawptr, path: cstring) -> NavigateResult,

	// Provides an initial alias override opportunity prior to searching for
	// configuration files. If .SUCCESS is returned, the internal state must be
	// updated to point at the aliased location. Can be nil.
	to_alias_override: proc "c" (L: ^State, ctx: rawptr, alias_unprefixed: cstring) -> NavigateResult,

	// Provides a final opportunity to resolve an alias if it cannot be found in
	// configuration files. If .SUCCESS is returned, the internal state must be
	// updated to point at the aliased location. Can be nil.
	to_alias_fallback: proc "c" (L: ^State, ctx: rawptr, alias_unprefixed: cstring) -> NavigateResult,

	// Navigates through the context by making mutations to the internal state.
	to_parent: proc "c" (L: ^State, ctx: rawptr) -> NavigateResult,
	to_child:  proc "c" (L: ^State, ctx: rawptr, name: cstring) -> NavigateResult,

	// Returns whether the context is currently pointing at a module.
	is_module_present: proc "c" (L: ^State, ctx: rawptr) -> c.bool,

	// Provides a chunkname for the current module. This will be accessible
	// through the debug library. Only called if `is_module_present` returns true.
	get_chunkname: proc "c" (
		L: ^State,
		ctx: rawptr,
		buffer: [^]u8,
		buffer_size: c.size_t,
		size_out: ^c.size_t,
	) -> WriteResult,

	// Provides a loadname that identifies the current module and is passed to
	// load. Only called if `is_module_present` returns true.
	get_loadname: proc "c" (
		L: ^State,
		ctx: rawptr,
		buffer: [^]u8,
		buffer_size: c.size_t,
		size_out: ^c.size_t,
	) -> WriteResult,

	// Provides a cache key representing the current module. Only called if
	// `is_module_present` returns true.
	get_cache_key: proc "c" (
		L: ^State,
		ctx: rawptr,
		buffer: [^]u8,
		buffer_size: c.size_t,
		size_out: ^c.size_t,
	) -> WriteResult,

	// Returns whether a configuration file is present in the current context,
	// and if so, its syntax. If not present, require-by-string will call
	// to_parent until either a configuration file is present or
	// .NOT_FOUND is returned (at root).
	get_config_status: proc "c" (L: ^State, ctx: rawptr) -> ConfigStatus,

	// Parses the configuration file in the current context for the given alias
	// and returns its value or .FAILURE if not found. Only called if
	// `get_config_status` returns .PRESENT_*. Mutually exclusive with
	// `get_config`.
	get_alias: proc "c" (
		L: ^State,
		ctx: rawptr,
		alias: cstring,
		buffer: [^]u8,
		buffer_size: c.size_t,
		size_out: ^c.size_t,
	) -> WriteResult,

	// Provides the contents of the configuration file in the current context.
	// Only called if `get_config_status` does not return .ABSENT. Mutually
	// exclusive with `get_alias`.
	get_config: proc "c" (
		L: ^State,
		ctx: rawptr,
		buffer: [^]u8,
		buffer_size: c.size_t,
		size_out: ^c.size_t,
	) -> WriteResult,

	// Returns the maximum number of milliseconds to allow for executing a given
	// Luau-syntax configuration file. Only called if `get_config_status`
	// returns .PRESENT_LUAU, and may be nil if Luau-syntax config support is
	// not needed. Defaults to 2000ms; negative values are treated as infinite.
	get_luau_config_timeout: proc "c" (L: ^State, ctx: rawptr) -> c.int,

	// Executes the module and places the result on the stack. Returns the
	// number of results placed on the stack. Returning -1 directs the requiring
	// thread to yield; in this case, this thread should be resumed with the
	// module result pushed onto its stack.
	//
	// For modules that use `export`, call `luarequire_createplaceholder(L)`
	// after compile to enable cyclic require support.
	load: proc "c" (
		L: ^State,
		ctx: rawptr,
		path: cstring,
		chunkname: cstring,
		loadname: cstring,
	) -> c.int,
}

// Populates function pointers in the given luarequire_Configuration.
Configuration_init :: #type proc "c" (config: ^Configuration)

@(link_prefix = "luarequire_", default_calling_convention="c")
foreign LuauRequire {
	// Initializes and pushes the require closure onto the stack without
	// registration.
	pushrequire :: proc (L: ^State, config_init: Configuration_init, ctx: rawptr) -> c.int ---

	// Initializes the require library and registers it globally.
	@(link_prefix = "luaopen_")
	require :: proc (L: ^State, config_init: Configuration_init, ctx: rawptr) ---

	// Initializes and pushes a "proxyrequire" closure onto the stack. This function
	// takes two parameters: the string path to resolve and the chunkname of an
	// existing module. The path is resolved as if it were being required from the
	// module that the chunkname represents.
	pushproxyrequire :: proc (L: ^State, config_init: Configuration_init, ctx: rawptr) -> c.int ---

	// Registers an aliased require path to a result. After registration, the given
	// result will always be immediately returned when the given path is required.
	// Expects the path and table to be passed as arguments on the stack.
	registermodule :: proc (L: ^State) -> c.int ---

	// Clears the entry associated with the given cache key from the require cache.
	// Expects the cache key to be passed as an argument on the stack.
	clearcacheentry :: proc (L: ^State) -> c.int ---

	// Clears all entries from the require cache.
	clearcache :: proc (L: ^State) -> c.int ---

	// Locks a placeholder table with error-throwing __index/__newindex metatables
	// to prevent access during cyclic module loading.
	lockplaceholder :: proc (L: ^State, idx: c.int) ---

	// Copies all fields, metatable, and readonly state from the result table into
	// the placeholder table, replacing the lock metatable.
	populateplaceholder :: proc (L: ^State, placeholderIdx, resultIdx: c.int) ---

	// Creates a locked placeholder and caches it for the current module.
	// Call from the load callback for modules that use export.
	createplaceholder :: proc (L: ^State) ---
}

/******************************************************************************
 * Copyright (c) 2019-2023 Roblox Corporation
 * Copyright (C) 1994-2008 Lua.org, PUC-Rio.  All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 ******************************************************************************/
