// Based on https://github.com/luau-lang/luau/blob/master/VM/include/lualib.h

package luau_vm_L
import "core:c"
import "core:mem"
import "base:intrinsics"
import "../lua"

when ODIN_OS == .Windows {
	foreign import LuauVM {
		"../target/lib/Luau.VM.lib",
	}
} else {
	foreign import LuauVM {
		"../target/lib/Luau.VM.a",
	}
}

State     :: lua.State
CFunction :: lua.CFunction
VECTOR_TYPE :: lua.VECTOR_TYPE
BUFFERSIZE  :: lua.BUFFERSIZE

Reg :: struct {
	name: cstring,
	func: CFunction,
}

// struct luaL_Strbuf (a.k.a. luaL_Buffer in the C headers).
Strbuf :: struct {
	p:       [^]c.char,   // current position in buffer
	end:     [^]c.char,   // end of the current buffer
	L:       ^State,
	storage: rawptr,      // struct TString* (opaque)
	buffer:  [BUFFERSIZE]c.char,
}

// Header calls this type luaL_Buffer; renamed to Strbuf to avoid confusion
// with the VM's internal buffer type.
Buffer :: Strbuf

@(link_prefix = "luaL_", default_calling_convention="c")
foreign LuauVM {
	register     :: proc(L: ^State, libname: cstring, l: [^]Reg) ---
	getmetafield :: proc(L: ^State, obj: c.int, e: cstring) -> c.int ---
	callmeta     :: proc(L: ^State, obj: c.int, e: cstring) -> c.int ---
	typeerrorL   :: proc(L: ^State, narg: c.int, tname: cstring) -> ! ---
	argerrorL    :: proc(L: ^State, narg: c.int, extramsg: cstring) -> ! ---
	checklstring :: proc(L: ^State, numArg: c.int, l: ^c.size_t) -> cstring ---
	optlstring   :: proc(L: ^State, numArg: c.int, def: cstring, l: ^c.size_t) -> cstring ---
	checknumber  :: proc(L: ^State, numArg: c.int) -> c.double ---
	optnumber    :: proc(L: ^State, nArg: c.int, def: c.double) -> c.double ---

	checkboolean :: proc(L: ^State, narg: c.int) -> c.int ---
	optboolean   :: proc(L: ^State, narg, def: c.int) -> c.int ---

	checkinteger   :: proc(L: ^State, numArg: c.int) -> c.int ---
	checkinteger64 :: proc(L: ^State, numArg: c.int) -> i64 ---
	optinteger     :: proc(L: ^State, nArg: c.int, def: c.int) -> c.int ---
	optinteger64   :: proc(L: ^State, nArg: c.int, def: i64) -> i64 ---
	checkunsigned  :: proc(L: ^State, numArg: c.int) -> c.uint ---
	optunsigned    :: proc(L: ^State, numArg: c.int, def: c.uint) -> c.uint ---

	checkvector :: proc(L: ^State, narg: c.int) -> [^]VECTOR_TYPE ---
	optvector   :: proc(L: ^State, narg: c.int, def: [^]VECTOR_TYPE) -> [^]VECTOR_TYPE ---

	checkstack :: proc(L: ^State, sz: c.int, msg: cstring) ---
	checktype  :: proc(L: ^State, narg, t: c.int) ---
	checkany   :: proc(L: ^State, narg: c.int) ---

	newmetatable     :: proc(L: ^State, tname: cstring) -> c.int ---
	checkudata       :: proc(L: ^State, ud: c.int, tname: cstring) -> rawptr ---
	checkudatatagged :: proc(L: ^State, ud: c.int, tag: c.int) -> rawptr ---

	checkbuffer :: proc(L: ^State, narg: c.int, len: ^c.size_t) -> rawptr ---

	@(link_name = "luaL_where")
	_where :: proc(L: ^State, lvl: c.int) ---

	errorL :: proc(L: ^State, fmt: cstring, #c_vararg args: ..any) -> ! ---

	checkoption :: proc(L: ^State, narg: c.int, def: cstring, lst: [^]cstring) -> c.int ---

	tolstring :: proc(L: ^State, idx: c.int, len: ^c.size_t) -> cstring ---

	newstate :: proc() -> ^State ---

	findtable :: proc(L: ^State, idx: c.int, fname: cstring, szhint: c.int) -> cstring ---

	typename :: proc(L: ^State, idx: c.int) -> cstring ---

	traceback :: proc(L: ^State, L1: ^State, msg: cstring, level: c.int) ---

	// ---- luaL_Strbuf / luaL_Buffer API ----
	buffinit       :: proc(L: ^State, B: ^Strbuf) ---
	buffinitsize   :: proc(L: ^State, B: ^Strbuf, size: c.size_t) -> [^]c.char ---
	prepbuffsize   :: proc(B: ^Strbuf, size: c.size_t) -> [^]c.char ---
	addlstring     :: proc(B: ^Strbuf, s: cstring, l: c.size_t) ---
	addvalue       :: proc(B: ^Strbuf) ---
	addvalueany    :: proc(B: ^Strbuf, idx: c.int) ---
	pushresult     :: proc(B: ^Strbuf) ---
	pushresultsize :: proc(B: ^Strbuf, size: c.size_t) ---
}

// ---------------------------------------------------------------------------
// Macro wrappers
// ---------------------------------------------------------------------------

error :: errorL
typeerror :: typeerrorL
argerror :: argerrorL

argcheck :: proc "c" (L: ^State, cond: bool, arg: c.int, extramsg: cstring) {
	if !cond {
		argerrorL(L, arg, extramsg)
	}
}

argexpected :: proc "c" (L: ^State, cond: bool, arg: c.int, tname: cstring) {
	if !cond {
		typeerrorL(L, arg, tname)
	}
}

checkstring :: proc "c" (L: ^State, numArg: c.int) -> string {
	return string(checklstring(L, numArg, nil))
}

optstring :: proc "c" (L: ^State, numArg: c.int, def: cstring) -> string {
	return string(optlstring(L, numArg, def, nil))
}

// #define luaL_getmetatable(L, n) (lua_getfield(L, LUA_REGISTRYINDEX, (n)))
getmetatable :: proc "c" (L: ^State, n: cstring) -> c.int {
	return lua.getfield(L, lua.REGISTRYINDEX, n)
}

// #define luaL_opt(L, f, n, d) (lua_isnoneornil(L, (n)) ? (d) : f(L, (n)))
// Generic port of the macro. Example:
//     luau_vm_L.opt(L, luau_vm_L.checkinteger, 1, 42)
opt :: #force_inline proc "c" (
	L: ^State,
	f: #type proc "c" (L: ^State, n: c.int) -> $T,
	n: c.int,
	d: T,
) -> T {
	if lua.isnoneornil(L, n) {
		return d
	}
	return f(L, n)
}

// #define luaL_callyieldable(L, nargs, nresults) lua_callyieldable(L, nargs, nresults)
callyieldable :: #force_inline proc "c" (L: ^State, nargs, nresults: c.int) -> c.int {
	return lua.callyieldable(L, nargs, nresults)
}

// #define luaL_pcallyieldable(L, nargs, nresults, errfunc) lua_pcallyieldable(L, nargs, nresults, errfunc)
pcallyieldable :: #force_inline proc "c" (L: ^State, nargs, nresults, errfunc: c.int) -> c.int {
	return lua.pcallyieldable(L, nargs, nresults, errfunc)
}

// #define luaL_addchar(B, c) ((void)((B)->p < (B)->end || luaL_prepbuffsize(B, 1)), (*(B)->p++ = (char)(c)))
addchar :: #force_inline proc "c" (B: ^Strbuf, c_in: c.char) {
	if uintptr(B.p) >= uintptr(B.end) {
		_ = prepbuffsize(B, 1)
	}
	B.p[0] = c_in
	B.p = mem.ptr_offset(B.p, 1)
}

// #define luaL_addstring(B, s) luaL_addlstring(B, s, strlen(s))
addstring :: #force_inline proc "c" (B: ^Strbuf, s: cstring) {
	n: c.size_t = 0
	p := cast([^]u8)s
	for p[n] != 0 {
		n += 1
	}
	addlstring(B, s, n)
}

// ---------------------------------------------------------------------------
// Builtin libraries
// ---------------------------------------------------------------------------

COLIBNAME     : cstring : "coroutine"
TABLIBNAME    : cstring : "table"
OSLIBNAME     : cstring : "os"
STRLIBNAME    : cstring : "string"
BITLIBNAME    : cstring : "bit32"
BUFFERLIBNAME : cstring : "buffer"
UTF8LIBNAME   : cstring : "utf8"
CLASSLIBNAME  : cstring : "class"
MATHLIBNAME   : cstring : "math"
DBLIBNAME     : cstring : "debug"
VECLIBNAME    : cstring : "vector"
INTLIBNAME    : cstring : "integer"

@(link_prefix = "lua", default_calling_convention="c")
foreign LuauVM {
	open_base      :: proc(L: ^State) -> c.int ---
	open_coroutine :: proc(L: ^State) -> c.int ---
	open_table     :: proc(L: ^State) -> c.int ---
	open_os        :: proc(L: ^State) -> c.int ---
	open_string    :: proc(L: ^State) -> c.int ---
	open_bit32     :: proc(L: ^State) -> c.int ---
	open_buffer    :: proc(L: ^State) -> c.int ---
	open_utf8      :: proc(L: ^State) -> c.int ---
	open_class     :: proc(L: ^State) -> c.int ---
	open_math      :: proc(L: ^State) -> c.int ---
	open_debug     :: proc(L: ^State) -> c.int ---
	open_vector    :: proc(L: ^State) -> c.int ---
	open_integer   :: proc(L: ^State) -> c.int ---
}

@(link_prefix = "luaL_", default_calling_convention="c")
foreign LuauVM {
	openlibs      :: proc(L: ^State) ---
	sandbox       :: proc(L: ^State) ---
	sandboxthread :: proc(L: ^State) ---
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
