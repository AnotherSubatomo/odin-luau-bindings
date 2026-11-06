// Based on: https://github.com/luau-lang/luau/blob/master/CodeGen/include/luacodegen.h

package luau_codegen
import "core:c"
import "../lua"

when ODIN_OS == .Windows {
	foreign import LuauCodegen {
		"../target/lib/Luau.CodeGen.lib",
	}
} else {
	foreign import LuauCodegen {
		"../target/lib/Luau.CodeGen.a",
	}
}

State :: lua.State

@(link_prefix = "luau_codegen_", default_calling_convention="c")
foreign LuauCodegen {
	// returns 1 if Luau code generator is supported, 0 otherwise
	supported :: proc () -> c.int ---

	// create an instance of Luau code generator. you must check that this feature is supported using luau_codegen_supported().
	create :: proc (L: ^State) ---

	// build target function and all inner functions
	compile :: proc (L: ^State, idx: c.int) ---
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
