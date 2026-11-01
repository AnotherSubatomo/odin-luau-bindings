// Based on https://github.com/luau-lang/luau/blob/master/VM/include/lua.h

package luau_vm
import "core:c"

when ODIN_OS == .Windows {
	foreign import LuauVM {
		"../target/lib/Luau.VM.lib",
	}
} else {
	foreign import LuauVM {
		"../target/lib/Luau.VM.a",
	}
}

// option for multiple returns in `lua_pcall' and `lua_call'
MULTRET :: (-1)

// pseudo-indices
REGISTRYINDEX :: (-MAXCSTACK - 2000)
ENVIRONINDEX  :: (-MAXCSTACK - 2001)
GLOBALSINDEX  :: (-MAXCSTACK - 2002)

upvalueindex :: #force_inline proc "c" (i: int) -> int { return GLOBALSINDEX - i }
ispseudo     :: #force_inline proc "c" (i: int) -> bool { return i <= REGISTRYINDEX }

// thread status
Status :: enum c.int {
	OK = 0,
	YIELD,
	ERRRUN,
	ERRSYNTAX, // legacy error code, preserved for compatibility
	ERRMEM,
	ERRERR,
	BREAK, // yielded for a debug breakpoint
}

CoStatus :: enum c.int {
	CORUN = 0, // running
	COSUS,     // suspended
	CONOR,     // 'normal' (it resumed another coroutine)
	COFIN,     // finished
	COERR,     // finished with error
}

State :: struct {}

CFunction    :: #type proc "c" (L: ^State) -> c.int
Continuation :: #type proc "c" (L: ^State, status: c.int) -> c.int

// prototype for memory-allocation functions
Alloc :: #type proc "c" (ud, ptr: rawptr, osize, nsize: c.size_t) -> rawptr

// `type` is an opaque VM-defined value which identifies the caged heap allocation kind
CageAlloc :: #type proc "c" (ud, ptr: rawptr, osize, nsize: c.size_t, type: c.int) -> rawptr

// destructor for userdata
Destructor :: #type proc "c" (L: ^State, userdata: rawptr)

// category name callback for memory dumps
CategoryName :: #type proc "c" (L: ^State, memcat: u8) -> cstring

// embedder GC callbacks
UserdataMark :: #type proc "c" (L: ^State, ud: rawptr)
EmbedderMark :: #type proc "c" (L: ^State, ref: c.int)
EmbedderGc   :: #type proc "c" (L: ^State, markref: EmbedderMark) -> c.int

// userdata direct-access callbacks
UserdataDirectAccess   :: #type proc "c" (L: ^State, data: rawptr, atom: c.int, cachedslot: ^u16, utag: c.int)
UserdataDirectNamecall :: #type proc "c" (L: ^State, data: rawptr, atom: c.int, cachedslot: ^u16, utag: c.int) -> c.int
UserdataDirectFieldGet :: #type proc "c" (ud: rawptr, result: rawptr)

// debug hook / coverage / counter callbacks
Hook            :: #type proc "c" (L: ^State, ar: ^Debug)
Coverage        :: #type proc "c" (ctx: rawptr, function: cstring, linedefined, depth: c.int, hits: [^]c.int, size: c.size_t)
CounterFunction :: #type proc "c" (ctx: rawptr, function: cstring, linedefined: c.int)
CounterValue    :: #type proc "c" (ctx: rawptr, kind, line: c.int, hits: u64)

// basic types
TNONE :: (-1)

when LUAU_VECTOR_DOUBLE {
	Type :: enum c.int {
		NIL = 0,     // must be 0 due to lua_isnoneornil
		BOOLEAN = 1, // must be 1 due to l_isfalse

		LIGHTUSERDATA,
		NUMBER,
		INTEGER,

		STRING,      // all above are value types, all below are GC types

		TABLE,
		FUNCTION,
		USERDATA,
		THREAD,
		BUFFER,
		CLASS,
		OBJECT,

		//When vector components are 'double', it is a GCObject with heap-allocated data
		VECTOR,

		// values below this line are used in GCObject tags but never in TValue tags
		DEADKEY,
		PROTO,
		UPVAL,

		// count of all Luau types
		_ALL,

		// count of TValue type tags
		_COUNT = DEADKEY,
	}
} else {
	Type :: enum c.int {
		NIL = 0,     // must be 0 due to lua_isnoneornil
		BOOLEAN = 1, // must be 1 due to l_isfalse

		LIGHTUSERDATA,
		NUMBER,
		INTEGER,

		// When vector components are 'float', vector fits into the TValue
		VECTOR,

		STRING,      // all above are value types, all below are GC types

		TABLE,
		FUNCTION,
		USERDATA,
		THREAD,
		BUFFER,
		CLASS,
		OBJECT,

		// values below this line are used in GCObject tags but never in TValue tags
		DEADKEY,
		PROTO,
		UPVAL,

		// count of all Luau types
		_ALL,

		// count of TValue type tags
		_COUNT = DEADKEY,
	}
}

Number   :: c.double
Integer  :: c.int
Unsigned :: c.uint

@(link_prefix="lua_")
foreign LuauVM {
	/*
	** state manipulation
	*/
	newstate      :: proc(f: Alloc, ud: rawptr) -> ^State ---
	close         :: proc(L: ^State) ---
	newthread     :: proc(L: ^State) -> ^State ---
	mainthread    :: proc(L: ^State) -> ^State ---
	resetthread   :: proc(L: ^State) ---
	isthreadreset :: proc(L: ^State) -> c.int ---

	/*
	** basic stack manipulation
	*/
	absindex      :: proc(L: ^State, idx: c.int) -> c.int ---
	gettop        :: proc(L: ^State) -> c.int ---
	settop        :: proc(L: ^State, idx: c.int) ---
	pushvalue     :: proc(L: ^State, idx: c.int) ---
	remove        :: proc(L: ^State, idx: c.int) ---
	insert        :: proc(L: ^State, idx: c.int) ---
	replace       :: proc(L: ^State, idx: c.int) ---
	checkstack    :: proc(L: ^State, sz: c.int) -> c.int ---
	rawcheckstack :: proc(L: ^State, sz: c.int) --- // allows unlimited stack frames

	xmove :: proc(from: ^State, to: ^State, n: c.int) ---
	xpush :: proc(from: ^State, to: ^State, idx: c.int) ---

	/*
	** access functions (stack -> C)
	*/
	isnumber    :: proc(L: ^State, idx: c.int) -> c.int ---
	isstring    :: proc(L: ^State, idx: c.int) -> c.int ---
	isinteger64 :: proc(L: ^State, idx: c.int) -> c.int ---
	iscfunction :: proc(L: ^State, idx: c.int) -> c.int ---
	isLfunction :: proc(L: ^State, idx: c.int) -> c.int ---
	isuserdata  :: proc(L: ^State, idx: c.int) -> c.int ---
	type        :: proc(L: ^State, idx: c.int) -> Type ---
	typename    :: proc(L: ^State, tp: c.int) -> cstring ---

	equal    :: proc(L: ^State, idx1, idx2: c.int) -> c.int ---
	rawequal :: proc(L: ^State, idx1, idx2: c.int) -> c.int ---
	lessthan :: proc(L: ^State, idx1, idx2: c.int) -> c.int ---

	tonumberx             :: proc(L: ^State, idx: c.int, isnum: ^c.int) -> c.double ---
	tointegerx            :: proc(L: ^State, idx: c.int, isnum: ^c.int) -> c.int ---
	tounsignedx           :: proc(L: ^State, idx: c.int, isnum: ^c.int) -> c.uint ---
	tovector              :: proc(L: ^State, idx: c.int) -> [^]VECTOR_TYPE ---
	toboolean             :: proc(L: ^State, idx: c.int) -> c.int ---
	tointeger64           :: proc(L: ^State, idx: c.int, isinteger: ^c.int) -> i64 ---
	tolstring             :: proc(L: ^State, idx: c.int, len: ^c.size_t) -> cstring ---
	tostringatom          :: proc(L: ^State, idx: c.int, atom: ^c.int) -> cstring ---
	tolstringatom         :: proc(L: ^State, idx: c.int, len: ^c.size_t, atom: ^c.int) -> cstring ---
	namecallatom          :: proc(L: ^State, atom: ^c.int) -> cstring ---
	objlen                :: proc(L: ^State, idx: c.int) -> c.int ---
	tocfunction           :: proc(L: ^State, idx: c.int) -> CFunction ---
	tolightuserdata       :: proc(L: ^State, idx: c.int) -> rawptr ---
	tolightuserdatatagged :: proc(L: ^State, idx: c.int, tag: c.int) -> rawptr ---
	touserdata            :: proc(L: ^State, idx: c.int) -> rawptr ---
	touserdatatagged      :: proc(L: ^State, idx: c.int, tag: c.int) -> rawptr ---
	userdatatag           :: proc(L: ^State, idx: c.int) -> c.int ---
	lightuserdatatag      :: proc(L: ^State, idx: c.int) -> c.int ---
	tothread              :: proc(L: ^State, idx: c.int) -> ^State ---
	tobuffer              :: proc(L: ^State, idx: c.int, len: ^c.size_t) -> rawptr ---
	topointer             :: proc(L: ^State, idx: c.int) -> rawptr ---

	/*
	** push functions (C -> stack)
	*/
	pushnil          :: proc(L: ^State) ---
	pushnumber       :: proc(L: ^State, n: c.double) ---
	pushinteger      :: proc(L: ^State, n: c.int) ---
	pushinteger64    :: proc(L: ^State, n: i64) ---
	pushunsigned     :: proc(L: ^State, n: c.uint) ---
	when VECTOR_SIZE == 4 {
		pushvector   :: proc(L: ^State, x, y, z, w: VECTOR_TYPE) ---
	} else {
		pushvector   :: proc(L: ^State, x, y, z: VECTOR_TYPE) ---
	}
	pushlstring      :: proc(L: ^State, s: cstring, l: c.size_t) ---
	pushstring       :: proc(L: ^State, s: cstring) ---
	pushvfstring     :: proc "c" (L: ^State, fmt: cstring, argp: cstring) -> cstring ---
	pushfstringL     :: proc "c" (L: ^State, fmt: cstring, #c_vararg args: ..any) -> cstring ---
	pushcclosurek    :: proc(L: ^State, fn: CFunction, debugname: cstring, nup: c.int, cont: Continuation) ---
	pushboolean      :: proc(L: ^State, b: c.int) ---
	pushthread       :: proc(L: ^State) -> c.int ---

	// `lua_Destructor` is defined as `Destructor`

	pushlightuserdatatagged :: proc(L: ^State, p: rawptr, tag: c.int) ---
	newuserdatatagged       :: proc(L: ^State, sz: c.size_t, tag: c.int) -> rawptr ---
	newuserdatataggedwithmetatable :: proc(L: ^State, sz: c.size_t, tag: c.int) -> rawptr ---
	newuserdatadtor         :: proc(L: ^State, sz: c.size_t, dtor: Destructor) -> rawptr ---

	newbuffer               :: proc(L: ^State, sz: c.size_t) -> rawptr ---

	/*
	** get functions (Lua -> stack)
	*/
	gettable    :: proc(L: ^State, idx: c.int) -> c.int ---
	getfield    :: proc(L: ^State, idx: c.int, k: cstring) -> c.int ---
	rawgetfield :: proc(L: ^State, idx: c.int, k: cstring) -> c.int ---
	rawget      :: proc(L: ^State, idx: c.int) -> c.int ---
	rawgeti     :: proc(L: ^State, idx, n: c.int) -> c.int ---
	rawgetptagged :: proc(L: ^State, idx: c.int, p: rawptr, tag: c.int) -> c.int ---
	createtable :: proc(L: ^State, narr, nrec: c.int) ---

	setreadonly :: proc(L: ^State, idx, enabled: c.int) ---
	getreadonly :: proc(L: ^State, idx: c.int) -> c.int ---
	setsafeenv  :: proc(L: ^State, idx, enabled: c.int) ---

	getmetatable :: proc(L: ^State, objindex: c.int) -> c.int ---
	getfenv      :: proc(L: ^State, idx: c.int) ---

	/*
	** set functions (stack -> Lua)
	*/
	settable     :: proc(L: ^State, idx: c.int) ---
	setfield     :: proc(L: ^State, idx: c.int, k: cstring) ---
	rawsetfield  :: proc(L: ^State, idx: c.int, k: cstring) ---
	rawset       :: proc(L: ^State, idx: c.int) ---
	rawseti      :: proc(L: ^State, idx, n: c.int) ---
	rawsetptagged :: proc(L: ^State, idx: c.int, p: rawptr, tag: c.int) ---
	setmetatable :: proc(L: ^State, objindex: c.int) -> c.int ---
	setfenv      :: proc(L: ^State, idx: c.int) -> c.int ---

	/*
	** `call' functions (run Luau bytecode)
	*/

	call   :: proc(L: ^State, nargs, nresults: c.int) ---
	pcall  :: proc(L: ^State, nargs, nresults, errfunc: c.int) -> Status ---
	cpcall :: proc(L: ^State, fn: CFunction, ud: rawptr) -> c.int ---

	callyieldable  :: proc(L: ^State, nargs, nresults: c.int) -> c.int ---
	pcallyieldable :: proc(L: ^State, nargs, nresults, errfunc: c.int) -> c.int ---

	/*
	** coroutine functions
	*/
	yield         :: proc(L: ^State, nresults: c.int) -> c.int ---
	@(link_name="lua_break")
	break_co      :: proc(L: ^State) -> c.int ---
	resume        :: proc(L: ^State, from: ^State, narg: c.int) -> c.int ---
	resumeerror   :: proc(L: ^State, from: ^State) -> c.int ---
	status        :: proc(L: ^State) -> c.int ---
	isyieldable   :: proc(L: ^State) -> c.int ---
	getthreaddata :: proc(L: ^State) -> rawptr ---
	setthreaddata :: proc(L: ^State, data: rawptr) ---
	costatus      :: proc(L: ^State, co: ^State) -> c.int ---
	hasfinalizers :: proc(L: ^State) -> c.int ---
	pushfinalizerfunction :: proc(L: ^State, co: ^State, toclose: c.int) ---
	addfinalizer  :: proc(L: ^State, co: ^State, idx: c.int) ---
}

/*
** `load' function (load Luau bytecode)
*/
foreign LuauVM {
	@(link_name="luau_load")
	load :: proc(L: ^State, chunkname: cstring, data: cstring, size: c.size_t, env: c.int) -> Status ---
}

/*
** garbage-collection function and options
*/

GCOp :: enum c.int {
	// stop and resume incremental garbage collection
	GCSTOP,
	GCRESTART,

	// run a full GC cycle; not recommended for latency sensitive applications
	GCCOLLECT,

	// return the heap size in KB and the remainder in bytes
	GCCOUNT,
	GCCOUNTB,

	// return 1 if GC is active (not stopped); note that GC may not be actively collecting even if it's running
	GCISRUNNING,

	// perform an explicit GC step, with the step size specified in KB
	GCSTEP,

	// tune GC parameters G (goal), S (step multiplier) and step size
	GCSETGOAL,
	GCSETSTEPMUL,
	GCSETSTEPSIZE,

	// return 1 if GC is in a paused state; making a GC step in a paused state will unpause the GC
	GCISPAUSED,
}

@(link_prefix = "lua_")
foreign LuauVM {
	gc :: proc(L: ^State, what, data: c.int) -> c.int ---

	// `lua_CategoryName` is defined as `CategoryName`

	// write a Luau memory dump to a FILE in JSON format
	// categoryName callback, when provided, will be called to record a name associated with the category
	memorydump :: proc(L: ^State, file: rawptr, categoryName: CategoryName) ---

	/*
	** memory statistics
	** all allocated bytes are attributed to the memory category of the running thread (0..LUA_MEMORY_CATEGORIES-1)
	*/
	setmemcat  :: proc(L: ^State, category: c.int) ---
	totalbytes :: proc(L: ^State, category: c.int) -> c.size_t ---

	// measure the allocation rate in bytes/sec
	// returns -1 if allocation rate cannot be measured
	allocationrate :: proc(L: ^State) -> i64 ---

	/*
	** miscellaneous functions
	*/
	error :: proc(L: ^State) -> ! ---

	next    :: proc(L: ^State, idx: c.int) -> c.int ---
	rawiter :: proc(L: ^State, idx, iter: c.int) -> c.int ---

	concat :: proc(L: ^State, n: c.int) ---

	setpointerencodekey :: proc(L: ^State, a, b, c, d: u64) ---
	encodepointer       :: proc(L: ^State, p: c.uintptr_t) -> c.uintptr_t ---

	clock :: proc() -> c.double ---

	setuserdatatag  :: proc(L: ^State, idx, tag: c.int) ---

	setuserdatadtor :: proc(L: ^State, tag: c.int, dtor: Destructor) ---
	getuserdatadtor :: proc(L: ^State, tag: c.int) -> Destructor ---

	// Embedder GC integration
	// `lua_UserdataMark` is defined as `UserdataMark`
	// `lua_EmbedderMark` is defined as `EmbedderMark`
	// `lua_EmbedderGc` is defined as `EmbedderGc`
	setuserdatamark :: proc(L: ^State, tag: c.int, markfn: UserdataMark) ---
	setembeddergc   :: proc(L: ^State, fn: EmbedderGc) ---

	// Embedder-managed weak references
	weakref    :: proc(L: ^State, idx: c.int) -> c.int ---
	weakunref  :: proc(L: ^State, ref: c.int) -> c.int ---
	getweakref :: proc(L: ^State, ref: c.int) -> c.int ---

	// userdata metatable helpers
	setuserdatametatable :: proc(L: ^State, tag: c.int) ---
	getuserdatametatable :: proc(L: ^State, tag: c.int) ---

	getuserdataname      :: proc(L: ^State, tag: c.int) -> cstring ---

	// `lua_UserdataDirectAccess` is defined as `UserdataDirectAccess`
	// `lua_UserdataDirectNamecall` is defined as `UserdataDirectNamecall`
	// `lua_UserdataDirectFieldGet` is defined as `UserdataDirectFieldGet`

	// NOTE: experimental API and is subject to breaking changes
	// userdata direct-access registration
	registeruserdatadirectaccess :: proc(L: ^State, tag: c.int, get: UserdataDirectAccess, set: UserdataDirectAccess, namecall: UserdataDirectNamecall) -> c.int ---
	registeruserdatadirectfieldget :: proc(L: ^State, tag: c.int, field: cstring, fn: UserdataDirectFieldGet) ---

	// helpers for writing result values from direct field handlers
	userdatadirectfield_setnumber    :: proc(result: rawptr, n: c.double) ---
	when VECTOR_SIZE == 4 {
		userdatadirectfield_setvector :: proc(result: rawptr, x, y, z, w: VECTOR_TYPE) ---
	} else {
		userdatadirectfield_setvector :: proc(result: rawptr, x, y, z: VECTOR_TYPE) ---
	}
	userdatadirectfield_setboolean   :: proc(result: rawptr, b: c.int) ---
	userdatadirectfield_setinteger64 :: proc(result: rawptr, n: i64) ---
	userdatadirectfield_setnil       :: proc(result: rawptr) ---

	setlightuserdataname :: proc(L: ^State, tag: c.int, name: cstring) ---
	getlightuserdataname :: proc(L: ^State, tag: c.int) -> cstring ---

	clonefunction :: proc(L: ^State, idx: c.int) ---
	usesexport    :: proc(L: ^State, idx: c.int) -> c.int ---

	cleartable :: proc(L: ^State, idx: c.int) ---
	clonetable :: proc(L: ^State, idx: c.int) ---

	getallocf :: proc(L: ^State, ud: ^rawptr) -> Alloc ---

	/*
	** reference system, can be used to pin objects
	*/
	ref   :: proc(L: ^State, idx: c.int) -> c.int ---
	unref :: proc(L: ^State, ref: c.int) -> c.int ---
}

NOREF   :: (-1)
REFNIL  :: 0

getref :: proc "c" (L: ^State, ref: c.int) -> c.int { return rawgeti(L, REGISTRYINDEX, ref) }

/*
** ===============================================================
** some useful macros
** ===============================================================
*/
tonumber   :: #force_inline proc "c" (L: ^State, #any_int i: c.int) -> c.double { return tonumberx(L, i, nil) }
tointeger  :: #force_inline proc "c" (L: ^State, #any_int i: c.int) -> c.int    { return tointegerx(L, i, nil) }
tounsigned :: #force_inline proc "c" (L: ^State, #any_int i: c.int) -> c.uint   { return tounsignedx(L, i, nil) }

pop :: #force_inline proc "c" (L: ^State, #any_int n: c.int) { settop(L, -n - 1) }

newtable    :: #force_inline proc "c" (L: ^State) { createtable(L, 0, 0) }
newuserdata :: #force_inline proc "c" (L: ^State, #any_int s: c.size_t) -> rawptr { return newuserdatatagged(L, s, 0) }

strlen :: #force_inline proc "c" (L: ^State, #any_int i: c.int) -> c.int { return objlen(L, i) }

isfunction      :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .FUNCTION }
istable         :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .TABLE }
islightuserdata :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .LIGHTUSERDATA }
isnil           :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .NIL }
isboolean       :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .BOOLEAN }
isinteger       :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .INTEGER }
isvector        :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .VECTOR }
isthread        :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .THREAD }
isbuffer        :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .BUFFER }
isnone          :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return cast(c.int) type(L, n) == TNONE }
isnoneornil     :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) <= .NIL }
isclass         :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .CLASS }
isobject        :: #force_inline proc "c" (L: ^State, n: c.int) -> bool { return type(L, n) == .OBJECT }
is              :: #force_inline proc "c" (L: ^State, n: c.int, t: Type) -> bool { return type(L, n) == t }

pushliteral       :: #force_inline proc "c" (L: ^State, s: string) { pushlstring(L, cast(cstring) raw_data(s), cast(c.size_t) len(s)) }
pushcfunction     :: #force_inline proc "c" (L: ^State, fn: CFunction, debug_name: cstring) { pushcclosurek(L, fn, debug_name, 0, nil) }
pushcclosure      :: #force_inline proc "c" (L: ^State, fn: CFunction, debug_name: cstring, nup: c.int) { pushcclosurek(L, fn, debug_name, nup, nil) }
pushlightuserdata :: #force_inline proc "c" (L: ^State, p: rawptr) { pushlightuserdatatagged(L, p, 0) }

rawgetp :: #force_inline proc "c" (L: ^State, idx: c.int, p: rawptr) -> c.int { return rawgetptagged(L, idx, p, 0) }
rawsetp :: #force_inline proc "c" (L: ^State, idx: c.int, p: rawptr) { rawsetptagged(L, idx, p, 0) }

setglobal :: #force_inline proc "c" (L: ^State, s: cstring) { setfield(L, GLOBALSINDEX, s) }
getglobal :: #force_inline proc "c" (L: ^State, s: cstring) -> c.int { return getfield(L, GLOBALSINDEX, s) }
tostring  :: #force_inline proc "c" (L: ^State, i: c.int) -> string { return string(tolstring(L, i, nil)) }

pushfstring :: pushfstringL

/*
** =======================================================================
** Debug API
** =======================================================================
*/
Debug :: struct {
	name, what, source, short_src: cstring,
	linedefined, currentline: c.int,
	protoid, bytecodeid: c.int,
	nupvals, nparams: c.uchar,
	isvararg: c.char,
	userdata: rawptr,
	ssbuf: [IDSIZE]c.char,
}

// `lua_Hook` is defined as `Hook`
// `lua_Coverage` is defined as `Coverage`
// `lua_CounterFunction` is defined as `CounterFunction`
// `lua_CounterValue` is defined as `CounterValue`

Callbacks :: struct {
	userdata: rawptr,

	interrupt:           #type proc "c" (L: ^State, gc: c.int),
	panic:               #type proc "c" (L: ^State, errcode: c.int),

	userthread:          #type proc "c" (LP: ^State, L: ^State),
	useratom:            #type proc "c" (L: ^State, s: cstring, l: c.size_t) -> i16,

	// NOTE: experimental — requires a Debug flag to be called
	userfinalizer:       #type proc "c" (L: ^State, co: ^State),

	debugbreak:          #type proc "c" (L: ^State, ar: ^Debug),
	debugstep:           #type proc "c" (L: ^State, ar: ^Debug),
	debuginterrupt:      #type proc "c" (L: ^State, ar: ^Debug),
	debugprotectederror: #type proc "c" (L: ^State),

	onallocate:          #type proc "c" (L: ^State, block: rawptr, osize, nsize: c.size_t, memcat: u8, tt: c.int, tag: c.int),

	preresume:           #type proc "c" (L: ^State),
	postresume:          #type proc "c" (L: ^State),

	onfree:              #type proc "c" (L: ^State, block: rawptr),
}

@(link_prefix = "lua_")
foreign LuauVM {
	// invoke a debug hook on a thread in break/yield state
	// userdata is passed to hook through lua_Debug::userdata field
	callhook :: proc(L: ^State, hook: Hook, userdata: rawptr) ---

	stackdepth  :: proc(L: ^State) -> c.int ---
	getinfo     :: proc(L: ^State, level: c.int, what: cstring, ar: ^Debug) -> c.int ---
	getargument :: proc(L: ^State, level, n: c.int) -> c.int ---
	getlocal    :: proc(L: ^State, level, n: c.int) -> cstring ---
	setlocal    :: proc(L: ^State, level, n: c.int) -> cstring ---
	getupvalue  :: proc(L: ^State, funcindex, n: c.int) -> cstring ---
	setupvalue  :: proc(L: ^State, funcindex, n: c.int) -> cstring ---

	hascustomexecution :: proc(L: ^State, level: c.int) -> c.int --- // function has custom execution data set
	incustomexecution  :: proc(L: ^State, level: c.int) -> c.int --- // function is running using custom execution

	singlestep :: proc(L: ^State, enabled: b32) ---
	breakpoint :: proc(L: ^State, funcindex, line: c.int, enabled: b32) -> c.int ---

	// returns 1 if execution is currently at a breakpoint; call only from debug callbacks
	atbreakpoint :: proc(L: ^State) -> c.int ---

	// Warning: not thread-safe since it stores the result in a shared global array! Only use for debugging.
	debugtrace :: proc(L: ^State) -> cstring ---

	getcoverage :: proc(L: ^State, funcindex: c.int, ctx: rawptr, callback: Coverage) ---
	getcounters :: proc(L: ^State, funcindex: c.int, ctx: rawptr, functionvisit: CounterFunction, countervisit: CounterValue) ---

	callbacks :: proc(L: ^State) -> ^Callbacks ---

	setmemorycage :: proc(L: ^State, alloc: CageAlloc, ud: rawptr) ---
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
