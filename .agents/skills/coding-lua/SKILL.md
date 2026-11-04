---
name: coding-lua
description: Write, refactor, review, or test Lua with runtime-version compatibility, explicit module and state boundaries, safe table and metatable behavior, validated dynamic execution, and project-first quality gates. Use for Lua source, modules, and Lua or LuaJIT integration work.
compatibility: Requires the coding skill and the Lua or LuaJIT runtime, package tooling, native integration, and analysis tools selected by the project.
metadata:
  author: dragoscirjan
  version: "1.0"
  opencode/slash: "true"
---

# Lua coding

Apply the generic `coding` workflow, then apply the Lua-specific rules in this skill.

## Load the dependency

Locate the advertised `coding` skill by exact name and path. If it is not already loaded, read its `SKILL.md` before continuing.

If `coding` is unavailable, stop and ask the human to install or expose it. Do not install it automatically, copy its instructions into this skill, or assume its contents from memory.

## Follow the selected Lua runtime

Inspect the declared Lua or LuaJIT versions, host application, module loader, rockspecs and lock data, native modules, formatter and lint settings, tests, documentation, and CI before editing. Lua 5.1 through 5.4 and LuaJIT differ in syntax, standard libraries, integer and number behavior, garbage collection, and C APIs. Use the reference manual that matches the project runtime.

Use the [Lua 5.4 Reference Manual](https://www.lua.org/manual/5.4/manual.html) only as the current upstream reference when it matches the project, and use the [LuaRocks Lua Style Guide](https://github.com/luarocks/lua-style-guide) as established community guidance. Safe, internally consistent project and host-runtime conventions take precedence.

## Write idiomatic Lua

- Prefer `local` bindings and explicit module exports. Do not create or mutate globals unintentionally.
- Keep functions and data flow clear. Isolate I/O, clocks, randomness, host APIs, registry state, and mutable module state.
- Preserve distinctions among `nil`, `false`, missing table keys, and absent return values. Remember that table holes make sequence length and iteration behavior unreliable.
- Handle multiple returns, varargs, method-call syntax, and metamethod dispatch deliberately. Avoid clever metatable behavior that hides ownership or control flow.
- Keep module loading compatible with the project's `package.path`, `package.cpath`, bundling, and embedding rules.
- Propagate errors with useful context and preserve traceback information where the host can act on it. Use protected calls only at boundaries that can recover.
- Release files, handles, native resources, and temporary state on success and failure using mechanisms supported by the selected runtime.
- Preserve public module names, return shapes, serialization formats, and host integration unless the approved task changes them.

## Enforce Lua security boundaries

- Treat loaded chunks, configuration, network data, save data, environment values, paths, and native-module results as untrusted at entry points.
- Do not pass untrusted text to `load`, `loadfile`, `dofile`, legacy `loadstring`, or equivalent host APIs. A restricted environment is not safe if it exposes dangerous capabilities.
- Keep untrusted values out of `os.execute`, `io.popen`, shell command strings, format strings, module paths, and native calls without context-specific validation.
- Validate path containment, symlink behavior, archive entries, and module resolution when security depends on filesystem boundaries.
- Treat the debug library, bytecode loading, FFI, and C modules as privileged capabilities. Minimize what sandboxed code can reach.
- Bound parsing, pattern matching, recursion, allocation, and instruction use when attacker-controlled input can consume resources.
- Keep credentials and personal data out of source, logs, tracebacks, generated files, and serialized state.

## Test and run Lua gates

Use the project's commands, runtime, and configured tools first. When the project has no configured choice, ask before installing or configuring these fallbacks:

- [Busted](https://lunarmodules.github.io/busted/) for focused and broader tests
- [StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting
- [Luacheck](https://github.com/lunarmodules/luacheck) for linting and global-use checks
- syntax checking with the selected runtime's compatible compiler or interpreter
- [jscpd](https://jscpd.dev/) as the duplicate detector when the project has no configured alternative

Test observable behavior, nil and false cases, table boundaries, errors and cleanup, module loading, supported runtimes, native integration, and security regressions. Do not use a different `luac` version to validate bytecode or syntax compatibility.

Lua does not have one mature universal dependency-vulnerability audit. Report that category as unsupported when the project has no suitable configured tool; do not claim that LuaRocks resolution, linting, or tests satisfy it.

Apply only project-defined thresholds. Report every applicable gate as passed, failed, not run, or unsupported.
