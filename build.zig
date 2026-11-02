// Zig-based build system for Luau, for those who have Zig and not CMake.

// To build the static library binaries from scratch, run the command below (replacing the [target] accordingly):
// zig build --prefix ./src/target -DLUAU_EXTERN_C=true -DLUAU_STATIC_CRT=true -Dinstall-libs=true -Doptimize=small -Dtarget=[target]

// Example:
// zig build --prefix ./src/target -DLUAU_EXTERN_C=true -DLUAU_STATIC_CRT=true -Dinstall-libs=true -Doptimize=small -Dtarget=x86_64-windows-msvc -Dlibc=libc_paths.txt

const std = @import("std");
const builtin = @import("builtin");

/// Extracts the list of paths from the `sys_include_dir=` line of a Zig
/// libc file (e.g. `libc_paths.txt`).
///
/// The returned slices (`[]const []const u8`) are *borrowed* from `content`,
/// so `content` must stay alive as long as you use the result. Only the
/// outer slice is allocated and must be freed with `allocator.free(result)`.
fn parseSysIncludeDirs(
    allocator: std.mem.Allocator,
    content: []const u8,
) []const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer paths.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "sys_include_dir=")) continue;

        const raw_value = line["sys_include_dir=".len..];
        const value = std.mem.trim(u8, raw_value, "\"");

        var it = std.mem.tokenizeScalar(u8, value, ';');
        while (it.next()) |p| {
            const trimmed = std.mem.trim(u8, p, " \t");
            if (trimmed.len == 0) continue;
            paths.append(allocator, trimmed) catch @panic("out of memory");
        }
        break; // only one sys_include_dir line
    }

    return paths.toOwnedSlice(allocator) catch @panic("out of memory");
}

fn addIncludes(b: *std.Build, m: *std.Build.Module, luau_src_path: []const u8, paths: []const []const u8) void {
    for (paths) |p| m.addIncludePath(b.path(b.pathJoin(&.{ luau_src_path, p })));
}

fn applyCrtMacros(m: *std.Build.Module, STATIC_CRT: bool) void {
    if (STATIC_CRT) {
        m.addCMacro("_MT", "1");
    } else {
        m.addCMacro("_DLL", "1");
    }
}

const CreateOptions = struct {
    LIBC_PATHS: ?std.Build.LazyPath,
    FLAGS: []const []const u8,
    LUAU_SRC: []const u8,
    USE_MSVC: bool,
    STATIC_CRT: bool,
};

fn createExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    libs: []const *std.Build.Step.Compile,
    sources: []const []const u8,
    includes: []const []const u8,
    opt: CreateOptions,
) *std.Build.Step.Compile {
    // Create executable
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = !opt.USE_MSVC,
            .link_libc = opt.USE_MSVC,
        }),
        .linkage = if (opt.STATIC_CRT) .static else .dynamic,
    });
    // Add libc, if USE_MSVC
    if (opt.USE_MSVC) exe.setLibCFile(opt.LIBC_PATHS);
    // Add sources
    exe.root_module.addCSourceFiles(.{
        .root = b.path(opt.LUAU_SRC),
        .files = sources,
        .flags = opt.FLAGS,
    });
    // Add includes
    addIncludes(b, exe.root_module, opt.LUAU_SRC, includes);
    // Link libraries
    for (libs) |lib| exe.root_module.linkLibrary(lib);
    // link pthread for Unix-like systems
    if (target.result.os.tag == .linux or
        target.result.os.tag == .macos or
        target.result.os.tag == .ios)
    {
        exe.root_module.linkSystemLibrary("pthread", .{});
    }
    // Apply the CRT macros, if opted
    applyCrtMacros(exe.root_module, opt.STATIC_CRT);
    return exe;
}

fn createLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    libs: []const *std.Build.Step.Compile,
    sources: []const []const u8,
    includes: []const []const u8,
    opt: CreateOptions,
) *std.Build.Step.Compile {
    // Create library
    const lib = b.addLibrary(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = !opt.USE_MSVC,
            .link_libc = opt.USE_MSVC,
        }),
    });
    // Add libc, if USE_MSVC
    if (opt.USE_MSVC) lib.setLibCFile(opt.LIBC_PATHS);
    // Add sources
    lib.root_module.addCSourceFiles(.{
        .root = b.path(opt.LUAU_SRC),
        .files = sources,
        .flags = opt.FLAGS,
    });
    // Add includes
    addIncludes(b, lib.root_module, opt.LUAU_SRC, includes);
    // Link libraries
    for (libs) |other_lib| lib.root_module.linkLibrary(other_lib);
    // Apply the CRT macros, if opted
    applyCrtMacros(lib.root_module, opt.STATIC_CRT);
    return lib;
}

pub fn build(b: *std.Build) void {
    // -------------------- Version enforcement --------------------
    const min_version = std.SemanticVersion{ .major = 0, .minor = 15, .patch = 0 };
    const current_version = builtin.zig_version;

    if (current_version.order(min_version) == .lt) {
        std.debug.print("\n\x1b[31mError: Your Zig version ({}) is too old.\x1b[0m" ++
            "\x1b[32mMinimum required version is: {}\x1b[0m\n\n", .{ current_version, min_version });

        std.process.exit(1);
    }

    // -------------------- Options --------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const USE_MSVC = target.result.abi == .msvc;

    const LUAU_SRC = b.option([]const u8, "luau-src", " Path to Luau source directory") orelse "luau";
    const unsure_libc_paths = b.option([]const u8, "libc", "Provide a file which specifies libc paths") orelse null;
    const install_libs = b.option(bool, "install-libs", "Install libraries to zig-out/lib") orelse false;

    const LIBC_PATHS: ?std.Build.LazyPath = if (unsure_libc_paths) |p| b.path(p) else null;

    if (USE_MSVC and LIBC_PATHS == null) @panic("-Dlibc is required when targeting the MSVC ABI");

    const build_cli = b.option(bool, "LUAU_BUILD_CLI", "Build CLI tools") orelse false;
    const build_tests = b.option(bool, "LUAU_BUILD_TESTS", "Build tests") orelse false;
    const build_web = b.option(bool, "LUAU_BUILD_WEB", "Build web module") orelse false;
    const STATIC_CRT = b.option(bool, "LUAU_STATIC_CRT", "Link with the static CRT (/MT)") orelse false;
    const extern_c = b.option(bool, "LUAU_EXTERN_C", "Use extern C for all APIs") orelse false;
    const build_shared = b.option(bool, "LUAU_BUILD_SHARED", "Build as shared library") orelse false;

    // Compile time options for Luau features
    const vec_double = b.option(bool, "LUAU_VECTOR_DOUBLE", "Use 64-bit doubles for vector components") orelse false;
    const vec_four_wide = b.option(bool, "LUAU_VECTOR_FOUR_WIDE", "Enable 4-wide mode for vectors, adding a 'w' component") orelse false;

    if (build_shared and !extern_c) @panic("-DLUAU_BUILD_SHARED requires -DLUAU_EXTERN_C to be true");

    // Unsupport
    _ = build_tests;
    _ = build_web;
    _ = vec_double;
    _ = vec_four_wide;

    // -------------------- IO --------------------
    // Write to the build root so both the compiler's `-include` lookup
    // AND Zig's cache-dependency checker can find it as a literal path.
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // -------------------- Generate extern "C" header --------------------
    if (extern_c) {
        const prefix =
            "#pragma once\n" ++
            "#ifdef __cplusplus\n";

        const body_shared_msvc =
            "#define LUA_API extern \"C\" __declspec(dllexport)\n" ++
            "#define LUACODE_API extern \"C\" __declspec(dllexport)\n" ++
            "#define LUACODEGEN_API extern \"C\" __declspec(dllexport)\n";

        const body_shared_gcc =
            "#define LUA_API extern \"C\" __attribute__((visibility(\"default\")))\n" ++
            "#define LUACODE_API extern \"C\" __attribute__((visibility(\"default\")))\n" ++
            "#define LUACODEGEN_API extern \"C\" __attribute__((visibility(\"default\")))\n";

        const body_static =
            "#define LUA_API extern \"C\"\n" ++
            "#define LUACODE_API extern \"C\"\n" ++
            "#define LUACODEGEN_API extern \"C\"\n";

        const suffix =
            "#define LUA_USE_LONGJMP 1\n" ++
            "#endif\n";

        const body = if (build_shared and target.result.abi == .msvc)
            body_shared_msvc
        else if (build_shared)
            body_shared_gcc
        else
            body_static;

        const header = std.mem.concat(
            b.allocator,
            u8,
            &[_][]const u8{ prefix, body, suffix },
        ) catch @panic("out of memory");

        // cwd() is on std.Io.Dir, not on Io.
        std.Io.Dir.cwd().access(io, "luau_extern_c.h", .{}) catch {
            std.Io.Dir.cwd().writeFile(io, .{
                .sub_path = "luau_extern_c.h",
                .data = header,
            }) catch @panic("failed to write luau_extern_c.h");
        };
    }

    // -------------------- Flags --------------------
    // Zig 0.15+ std.ArrayList is the unmanaged variant (no .init), so we
    // simply prepare two const slices and pick the right one.
    const base_flags = [_][]const u8{
        "-D_CRT_SECURE_NO_WARNINGS",
        "-Wsign-compare",
        "-fexceptions",
        "-std=c++17",
    };
    const base_flags_with_include =
        base_flags ++ [_][]const u8{ "-include", "luau_extern_c.h" };
    const cpp17: []const []const u8 =
        if (extern_c) &base_flags_with_include else &base_flags;

    const create_opts = CreateOptions{
        .FLAGS = cpp17,
        .LIBC_PATHS = LIBC_PATHS,
        .STATIC_CRT = STATIC_CRT,
        .USE_MSVC = USE_MSVC,
        .LUAU_SRC = LUAU_SRC,
    };

    // -------------------- Include sets --------------------
    const inc_common = [_][]const u8{"Common/include"};
    const inc_ast = [_][]const u8{ "Ast/include", "Common/include" };
    const inc_bytecode = [_][]const u8{ "Bytecode/include", "Common/include" };
    const inc_vm = [_][]const u8{ "VM/include", "VM/src", "Common/include" };
    const inc_compiler = [_][]const u8{ "Compiler/include", "Compiler/src", "Ast/include", "Bytecode/include", "Common/include" };
    const inc_config = [_][]const u8{ "Config/include", "Ast/include", "Compiler/include", "VM/include", "Bytecode/include", "Common/include" };
    const inc_analysis = [_][]const u8{ "Analysis/include", "Config/include", "Ast/include", "Compiler/include", "VM/include", "Bytecode/include", "Common/include" };
    const inc_codegen = [_][]const u8{ "CodeGen/include", "CodeGen/src", "VM/include", "VM/src", "Common/include" };
    const inc_inliner = [_][]const u8{ "Inliner/include", "Inliner/src", "Bytecode/src", "Bytecode/include", "VM/src", "VM/include", "Common/include" };
    const inc_require = [_][]const u8{ "Require/include", "Require/src", "Config/include", "Ast/include", "Compiler/include", "VM/include", "Bytecode/include", "Common/include" };
    const inc_cli = [_][]const u8{ "CLI/include", "Common/include", "Config/include", "Ast/include", "Compiler/include", "VM/include", "Bytecode/include" };

    const inc_exe = [_][]const u8{
        "CLI/include",     "Common/include",          "Ast/include",     "Bytecode/include",
        "VM/include",      "Compiler/include",        "Config/include",  "Analysis/include",
        "CodeGen/include", "Inliner/include",         "Require/include", "Reduce/include",
        "extern",          "extern/isocline/include",
    };

    // ==================================================================
    // 1. Luau.Common
    // ==================================================================
    const common_lib = createLibrary(b, target, optimize, "Luau.Common", &.{}, &.{
        "Common/src/BytecodeWire.cpp",
        "Common/src/StringUtils.cpp",
        "Common/src/TimeTrace.cpp",
    }, &inc_common, create_opts);

    // ==================================================================
    // 2. Luau.Ast
    // ==================================================================
    const ast_lib = createLibrary(b, target, optimize, "Luau.Ast", &.{common_lib}, &.{
        "Ast/src/Allocator.cpp",
        "Ast/src/Ast.cpp",
        "Ast/src/Confusables.cpp",
        "Ast/src/Cst.cpp",
        "Ast/src/Lexer.cpp",
        "Ast/src/Location.cpp",
        "Ast/src/Parser.cpp",
        "Ast/src/PrettyPrinter.cpp",
    }, &inc_ast, create_opts);

    // ==================================================================
    // 3. Luau.Bytecode
    // ==================================================================
    const bytecode_lib = createLibrary(b, target, optimize, "Luau.Bytecode", &.{common_lib}, &.{
        "Bytecode/src/BytecodeBuilder.cpp",
        "Bytecode/src/BytecodeDump.cpp",
        "Bytecode/src/BytecodeGraph.cpp",
        "Bytecode/src/Sccp.cpp",
    }, &inc_bytecode, create_opts);

    // ==================================================================
    // 4. Luau.VM
    // ==================================================================
    const vm_lib = createLibrary(b, target, optimize, "Luau.VM", &.{common_lib}, &.{
        "VM/src/lapi.cpp",      "VM/src/laux.cpp",       "VM/src/lbaselib.cpp",
        "VM/src/lbitlib.cpp",   "VM/src/lbuffer.cpp",    "VM/src/lbuflib.cpp",
        "VM/src/lbuiltins.cpp", "VM/src/lcorolib.cpp",   "VM/src/ldblib.cpp",
        "VM/src/ldebug.cpp",    "VM/src/ldo.cpp",        "VM/src/lfunc.cpp",
        "VM/src/lgc.cpp",       "VM/src/lgcdebug.cpp",   "VM/src/linit.cpp",
        "VM/src/lmathlib.cpp",  "VM/src/lmem.cpp",       "VM/src/lnumprint.cpp",
        "VM/src/lobject.cpp",   "VM/src/loslib.cpp",     "VM/src/lperf.cpp",
        "VM/src/lstate.cpp",    "VM/src/lstring.cpp",    "VM/src/lstrlib.cpp",
        "VM/src/ltable.cpp",    "VM/src/ltablib.cpp",    "VM/src/ltm.cpp",
        "VM/src/ludata.cpp",    "VM/src/lutf8lib.cpp",   "VM/src/lveclib.cpp",
        "VM/src/lintlib.cpp",   "VM/src/lvmexecute.cpp", "VM/src/lclass.cpp",
        "VM/src/lclasslib.cpp", "VM/src/lvector.cpp",    "VM/src/lvmload.cpp",
        "VM/src/lvmutils.cpp",
    }, &inc_vm, create_opts);

    // Add `luau_init.cpp`, read more about it by opening the file
    vm_lib.root_module.addCSourceFile(.{ .file = b.path("luau_init.cpp"), .flags = create_opts.FLAGS });

    // ==================================================================
    // 5. Luau.Compiler
    // ==================================================================
    const compiler_lib = createLibrary(b, target, optimize, "Luau.Compiler", &.{ ast_lib, bytecode_lib }, &.{
        "Compiler/src/Compiler.cpp",
        "Compiler/src/Builtins.cpp",
        "Compiler/src/BuiltinFolding.cpp",
        "Compiler/src/ConstantFolding.cpp",
        "Compiler/src/CostModel.cpp",
        "Compiler/src/TableShape.cpp",
        "Compiler/src/Types.cpp",
        "Compiler/src/ValueTracking.cpp",
        "Compiler/src/lcode.cpp",
    }, &inc_compiler, create_opts);

    // ==================================================================
    // 6. Luau.Config
    // ==================================================================
    const config_lib = createLibrary(b, target, optimize, "Luau.Config", &.{ ast_lib, compiler_lib, vm_lib }, &.{
        "Config/src/Config.cpp",
        "Config/src/LinterConfig.cpp",
        "Config/src/LuauConfig.cpp",
    }, &inc_config, create_opts);

    // ==================================================================
    // 7. Luau.Analysis
    // ==================================================================
    const analysis_lib = createLibrary(b, target, optimize, "Luau.Analysis", &.{ ast_lib, config_lib, compiler_lib, vm_lib }, &.{
        "Analysis/src/Anyification.cpp",               "Analysis/src/ApplyTypeFunction.cpp",
        "Analysis/src/AstJsonEncoder.cpp",             "Analysis/src/AstQuery.cpp",
        "Analysis/src/AstUtils.cpp",                   "Analysis/src/Autocomplete.cpp",
        "Analysis/src/AutocompleteCore.cpp",           "Analysis/src/BuiltinDefinitions.cpp",
        "Analysis/src/BuiltinTypeFunctions.cpp",       "Analysis/src/Clone.cpp",
        "Analysis/src/Constraint.cpp",                 "Analysis/src/ConstraintGenerator.cpp",
        "Analysis/src/ConstraintGraph.cpp",            "Analysis/src/ConstraintSolver.cpp",
        "Analysis/src/ControlFlowGraph.cpp",           "Analysis/src/DumpCFG.cpp",
        "Analysis/src/TypeStateMap.cpp",               "Analysis/src/DataFlowGraph.cpp",
        "Analysis/src/DcrLogger.cpp",                  "Analysis/src/Def.cpp",
        "Analysis/src/EmbeddedBuiltinDefinitions.cpp", "Analysis/src/Error.cpp",
        "Analysis/src/ExpectedTypeVisitor.cpp",        "Analysis/src/FileResolver.cpp",
        "Analysis/src/FragmentAutocomplete.cpp",       "Analysis/src/Frontend.cpp",
        "Analysis/src/Generalization.cpp",             "Analysis/src/NativeStackGuard.cpp",
        "Analysis/src/GlobalTypes.cpp",                "Analysis/src/Instantiation.cpp",
        "Analysis/src/Instantiation2.cpp",             "Analysis/src/IostreamHelpers.cpp",
        "Analysis/src/IterativeTypeVisitor.cpp",       "Analysis/src/IterativeTypeFunctionTypeVisitor.cpp",
        "Analysis/src/JsonEmitter.cpp",                "Analysis/src/Linter.cpp",
        "Analysis/src/LValue.cpp",                     "Analysis/src/Module.cpp",
        "Analysis/src/NonStrictTypeChecker.cpp",       "Analysis/src/Normalize.cpp",
        "Analysis/src/OverloadResolver.cpp",           "Analysis/src/Quantify.cpp",
        "Analysis/src/RecursionCounter.cpp",           "Analysis/src/Refinement.cpp",
        "Analysis/src/RequireTracer.cpp",              "Analysis/src/Scope.cpp",
        "Analysis/src/Simplify.cpp",                   "Analysis/src/StructuralTypeEquality.cpp",
        "Analysis/src/Substitution.cpp",               "Analysis/src/Subtyping.cpp",
        "Analysis/src/Symbol.cpp",                     "Analysis/src/TableLiteralInference.cpp",
        "Analysis/src/ToDot.cpp",                      "Analysis/src/TopoSortStatements.cpp",
        "Analysis/src/ToString.cpp",                   "Analysis/src/TxnLog.cpp",
        "Analysis/src/Type.cpp",                       "Analysis/src/TypeArena.cpp",
        "Analysis/src/TypeAttach.cpp",                 "Analysis/src/TypeChecker2.cpp",
        "Analysis/src/TypedAllocator.cpp",             "Analysis/src/TypeFunction.cpp",
        "Analysis/src/TypeFunctionError.cpp",          "Analysis/src/TypeFunctionReductionGuesser.cpp",
        "Analysis/src/TypeFunctionRuntime.cpp",        "Analysis/src/TypeFunctionRuntimeBuilder.cpp",
        "Analysis/src/TypeIds.cpp",                    "Analysis/src/TypeInfer.cpp",
        "Analysis/src/TypeOrPack.cpp",                 "Analysis/src/TypePack.cpp",
        "Analysis/src/TypePath.cpp",                   "Analysis/src/TypeUtils.cpp",
        "Analysis/src/Unifiable.cpp",                  "Analysis/src/Unifier.cpp",
        "Analysis/src/Unifier2.cpp",                   "Analysis/src/UserDefinedTypeFunction.cpp",
    }, &inc_analysis, create_opts);

    // ==================================================================
    // 8. Luau.CodeGen
    // ==================================================================
    const codegen_lib = createLibrary(b, target, optimize, "Luau.CodeGen", &.{vm_lib}, &.{
        "CodeGen/src/AssemblyBuilderA64.cpp",      "CodeGen/src/AssemblyBuilderX64.cpp",
        "CodeGen/src/CodeAllocator.cpp",           "CodeGen/src/CodeBlockUnwind.cpp",
        "CodeGen/src/CodeGen.cpp",                 "CodeGen/src/CodeGenAssembly.cpp",
        "CodeGen/src/CodeGenContext.cpp",          "CodeGen/src/CodeGenUtils.cpp",
        "CodeGen/src/CodeGenA64.cpp",              "CodeGen/src/CodeGenX64.cpp",
        "CodeGen/src/EmitBuiltinsX64.cpp",         "CodeGen/src/EmitCommonX64.cpp",
        "CodeGen/src/EmitInstructionX64.cpp",      "CodeGen/src/IrAnalysis.cpp",
        "CodeGen/src/IrBuilder.cpp",               "CodeGen/src/IrCallWrapperX64.cpp",
        "CodeGen/src/IrDump.cpp",                  "CodeGen/src/IrLoweringA64.cpp",
        "CodeGen/src/IrLoweringX64.cpp",           "CodeGen/src/IrRegAllocA64.cpp",
        "CodeGen/src/IrRegAllocX64.cpp",           "CodeGen/src/IrTranslateBuiltins.cpp",
        "CodeGen/src/IrTranslation.cpp",           "CodeGen/src/IrUtils.cpp",
        "CodeGen/src/IrValueLocationTracking.cpp", "CodeGen/src/lcodegen.cpp",
        "CodeGen/src/NativeProtoExecData.cpp",     "CodeGen/src/NativeState.cpp",
        "CodeGen/src/OptimizeConstProp.cpp",       "CodeGen/src/OptimizeDeadStore.cpp",
        "CodeGen/src/OptimizeFinalX64.cpp",        "CodeGen/src/UnwindBuilderDwarf2.cpp",
        "CodeGen/src/UnwindBuilderWin.cpp",        "CodeGen/src/BytecodeAnalysis.cpp",
        "CodeGen/src/BytecodeSummary.cpp",         "CodeGen/src/SharedCodeAllocator.cpp",
    }, &inc_codegen, create_opts);

    // ==================================================================
    // 9. Luau.Inliner
    // ==================================================================
    const inliner_lib = createLibrary(b, target, optimize, "Luau.Inliner", &.{ vm_lib, bytecode_lib }, &.{
        "Inliner/src/JitInliner.cpp",
        "Inliner/src/TValueVmConstImpl.cpp",
        "Inliner/src/luajitinliner.cpp",
    }, &inc_inliner, create_opts);

    // ==================================================================
    // 10. Luau.Require
    // ==================================================================
    const require_lib = createLibrary(b, target, optimize, "Luau.Require", &.{ config_lib, vm_lib }, &.{
        "Require/src/AliasCycleTracker.cpp",
        "Require/src/Navigation.cpp",
        "Require/src/PathUtilities.cpp",
        "Require/src/Require.cpp",
        "Require/src/RequireImpl.cpp",
        "Require/src/RequireNavigator.cpp",
    }, &inc_require, create_opts);

    // ==================================================================
    // 11. Luau.CLI.lib
    // ==================================================================
    const cli_lib = createLibrary(b, target, optimize, "Luau.CLI.lib", &.{ common_lib, config_lib }, &.{
        "CLI/src/FileUtils.cpp",
        "CLI/src/Flags.cpp",
        "CLI/src/VfsNavigator.cpp",
    }, &inc_cli, create_opts);

    // ==================================================================
    // 12. isocline (C)
    // ==================================================================
    const isocline_lib = b.addLibrary(.{
        .name = "isocline",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    if (USE_MSVC) {
        isocline_lib.setLibCFile(LIBC_PATHS);
    }
    isocline_lib.root_module.addCSourceFiles(.{
        .root = b.path(LUAU_SRC),
        .files = &.{"extern/isocline/src/isocline.c"},
        .flags = &[_][]const u8{"-std=c11"},
    });
    isocline_lib.root_module.addIncludePath(b.path("extern/isocline/include"));
    applyCrtMacros(isocline_lib.root_module, STATIC_CRT);

    if (USE_MSVC and LIBC_PATHS != null) {
        // -------------------- Parse `sys_include_dir` --------------------
        const libc_paths_content = std.Io.Dir.cwd().readFileAlloc(
            io,
            unsure_libc_paths.?,
            b.allocator,
            .limited(0x100000), // 1 MiB cap
        ) catch |err| {
            std.debug.panic("failed to read {any}: {s}", .{ LIBC_PATHS, @errorName(err) });
        };
        defer b.allocator.free(libc_paths_content);

        const libc_include_dirs = parseSysIncludeDirs(b.allocator, libc_paths_content);
        defer b.allocator.free(libc_include_dirs);

        // -------------------- Add the system include paths --------------------
        for ([_]*std.Build.Step.Compile{
            common_lib, ast_lib,      bytecode_lib, vm_lib,      compiler_lib,
            config_lib, analysis_lib, codegen_lib,  inliner_lib, require_lib,
            cli_lib,    isocline_lib,
        }) |lib| {
            for (libc_include_dirs) |libc_include_dir| {
                lib.root_module.addSystemIncludePath(.{ .cwd_relative = libc_include_dir });
            }
        }
    }

    // ==================================================================
    // CLI executables
    // ==================================================================
    if (build_cli) {
        const repl_libs = &.{ compiler_lib, inliner_lib, config_lib, codegen_lib, vm_lib, require_lib, cli_lib, isocline_lib };
        const repl_exe = createExecutable(b, target, optimize, "luau", repl_libs, &.{
            "CLI/src/Repl.cpp",
            "CLI/src/ReplEntry.cpp",
            "CLI/src/ReplRequirer.cpp",
            "CLI/src/Counters.cpp",
            "CLI/src/Coverage.cpp",
            "CLI/src/Profiler.cpp",
        }, &inc_exe, create_opts);
        b.installArtifact(repl_exe);

        const analyze_libs = &.{ analysis_lib, cli_lib, require_lib };
        const analyze_exe = createExecutable(b, target, optimize, "luau-analyze", analyze_libs, &.{
            "CLI/src/Analyze.cpp",
            "CLI/src/AnalyzeRequirer.cpp",
        }, &inc_exe, create_opts);
        b.installArtifact(analyze_exe);

        const ast_libs = &.{ ast_lib, analysis_lib, cli_lib };
        const ast_exe = createExecutable(b, target, optimize, "luau-ast", ast_libs, &.{"CLI/src/Ast.cpp"}, &inc_exe, create_opts);
        b.installArtifact(ast_exe);

        const compile_libs = &.{ compiler_lib, vm_lib, codegen_lib, cli_lib };
        const compile_exe = createExecutable(b, target, optimize, "luau-compile", compile_libs, &.{"CLI/src/Compile.cpp"}, &inc_exe, create_opts);
        b.installArtifact(compile_exe);

        const bytecode_libs = &.{ compiler_lib, vm_lib, codegen_lib, cli_lib };
        const bytecode_exe = createExecutable(b, target, optimize, "luau-bytecode", bytecode_libs, &.{"CLI/src/Bytecode.cpp"}, &inc_exe, create_opts);
        b.installArtifact(bytecode_exe);

        const reduce_libs = &.{ common_lib, ast_lib, analysis_lib, cli_lib };
        const reduce_exe = createExecutable(b, target, optimize, "luau-reduce", reduce_libs, &.{"CLI/src/Reduce.cpp"}, &inc_exe, create_opts);
        b.installArtifact(reduce_exe);
    }

    // ==================================================================
    // Install libraries on request
    // ==================================================================
    if (install_libs) {
        b.installArtifact(common_lib);
        b.installArtifact(ast_lib);
        b.installArtifact(bytecode_lib);
        b.installArtifact(vm_lib);
        b.installArtifact(compiler_lib);
        b.installArtifact(config_lib);
        b.installArtifact(analysis_lib);
        b.installArtifact(codegen_lib);
        b.installArtifact(inliner_lib);
        b.installArtifact(require_lib);
        b.installArtifact(cli_lib);
        b.installArtifact(isocline_lib);
    }
}
