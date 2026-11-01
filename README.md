# Luau Bindings for Odin

This repo contains Odin bindings for the [Luau](https://luau-lang.org) programming language.

> [!WARNING]
> The binaries built and bundled at [`src/os`](src/os) are targeted to `x86_64-windows-msvc`. To target it to a different architecture, OS, and ABI -- rebuild the binaries yourself using the CMake or Makefile provided by [`luau`](luau), or the [`build.zig`](#buildzig) I have built as an alternative. Make sure to include the flags `-DLUAU_EXTERN_C=1` and `-DLUAU_STATIC_CRT=1` in your build command.

## Usage
The bindings try to provide a full and faithful coverage as much as possible. As far as I know, the bindings for `lua_break` (a specialized debugging function used to stop thread execution on a debug breakpoint) is the only difference apparent in this binding (it was binded to appear as `lua.break_co` due to `break` being a reserved keyword). Every API method in `LUA_API` and `LUALIB_API`, as of Luau 0.745, has been implemented.

You can read about the difference between Luau and Lua [here](https://luau-lang.org/compatibility). To read about the Luau API, go [here](https://luau.org/api)

Here is a simple `main.odin` that reads a file, compiles it and then executes it:
```odin
package main
import "core:os"
import "luau"
import "luau/lua"
import "luau/luaL"

main :: proc() {
    // You can see what these do in `luau.odin`. All of the original comments
    // are left untouched.
    options := luau.CompileOptions {
        optimization_level = 1,
        debug_level = 1,
        type_info_level = 0,
        coverage_level = 0,
    }

    source, _ := os.read_entire_file("main.luau")

    out_size: c.size_t
    code := luau.compile(cstr(string(source)), len(source), &options, &out_size)

    L := luaL.newstate()
    luaL.openlibs(L) // Makes the `print` function available.
    lua.load(L, "module", code, out_size, 0)
    lua.call(L, 0, 0)
}
```

## build.zig
The [`build.zig`](build.zig) file is a build system for Luau, written in Zig, for those who have already have the Zig toolchain available to them, but not that of CMake (...and for those who don't want to deal with the bloat of CMake).

To use it with respect to the structure of the repository, the recommended command is:
```sh
zig build --prefix ./src/target -DLUAU_EXTERN_C=true -DLUAU_STATIC_CRT=true -Dinstall-libs=true -Dtarget=[target]
```

Where `[target]` is changed according to `<arch><sub>-<os>-<abi>`, for example:
```sh
zig build --prefix ./src/target -DLUAU_EXTERN_C=true -DLUAU_STATIC_CRT=true -Dinstall-libs=true -Dtarget=x86_64-windows-gnu
```

If you're targetting the MSVC ABI, and you have a niche, custom, minimalist build of MSVC installed (like I do), which causes the `zig` CLI to not recognize the existence of `libc` in your system, you can write the paths to its directories down into a `.txt` file (as exemplified by [`libc_paths.txt`](libc_paths.txt)), and hook it onto your build command via the `-Dlibc=[path]` flag.
```sh
zig build --prefix ./src/target -DLUAU_EXTERN_C=true -DLUAU_STATIC_CRT=true -Dinstall-libs=true -Dtarget=x86_64-windows-msvc -Dlibc=libc_paths.txt
```