# Validation

Read this document before validating, committing, pushing, or publishing a repository change. Run the checks that match the changed files and behavior.

Record each check that ran. If a required or applicable check cannot run, state why. Do not claim that an unexecuted check passed.

## Every change

- Run `git diff --check`.
- Review `git status --short` and the complete diff.
- Confirm that only approved files changed.
- Check commands, paths, examples, and links manually.

## Lua and Neovim configuration

For Lua changes:

- Run `stylua --check .` when StyLua is available.
- Run `find init.lua lua -type f -name '*.lua' -exec luac -p {} +` when `luac` is available.
- Review plugin specifications for valid LazyVim and lazy.nvim structure.
- Confirm that platform-specific behavior remains guarded.

A Neovim startup smoke test is optional because it can bootstrap lazy.nvim, fetch plugins, or modify user data. Run `nvim --headless '+qa'` only with explicit owner approval in an environment where those effects are acceptable.

## Bash scripts

For changes to `whisper-install.sh` or `whisper-test.sh`:

- Run `bash -n whisper-install.sh whisper-test.sh`.
- Run `shellcheck -s bash whisper-install.sh whisper-test.sh` when ShellCheck is available.
- Do not run the scripts as a validation shortcut; they clone, build, download, remove, or execute user-level software.

## PowerShell script

For changes to `Build-LuaTiktoken.ps1`, run this parser check when PowerShell is available:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path 'Build-LuaTiktoken.ps1'),
  [ref]$tokens,
  [ref]$errors
) > $null
if ($errors.Count) {
  $errors | ForEach-Object { Write-Error $_ }
  exit 1
}
```

Do not run the build script merely to validate syntax.

## JSON and TOML configuration

When changing `lazyvim.json` or `.neoconf.json`, parse each changed JSON file with an available JSON parser. When changing `stylua.toml`, parse it with an available TOML parser. Report the parser and result.

## Agent assets

When synchronizing or changing agent assets:

- Verify that every selected skill directory name matches the `name` in its `SKILL.md` frontmatter.
- Verify that all selected dependencies and complete supporting files exist.
- Verify that Pi and OpenCode discover canonical skills under `.agents/skills/`.
- Verify that every Claude projection is the exact relative symlink `.claude/skills/<name> -> ../../.agents/skills/<name>`.
- Confirm that `CLAUDE.md` imports `AGENTS.md` before any Claude-specific instructions.
- Confirm that `skills-lock.json` reflects the Skills CLI installation.
- Confirm that `.agents/ai-assets.lock.json` contains no credentials, secrets, temporary paths, or personal absolute paths.
- Run `node .agents/skills/sync-agent-assets/scripts/sync-agent-assets.mjs status --root "$(git rev-parse --show-toplevel)"` and require clean managed state after recording.

## Instruction changes

When changing `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, or `VALIDATION.md`:

- Confirm that the owner approved the exact proposal before mutation.
- Confirm that `AGENTS.md` contains startup routing, project workspace settings, security boundaries, and owner authority rather than detailed procedures.
- Check for missing routes, stale paths, conflicts, duplication, ambiguity, and dependency cycles.
- Confirm that mandatory routes point only to installed files and skills.
- Confirm that security boundaries, mutation gates, validation requirements, and owner authority match the approved proposal.

## Publication

Validation does not authorize publication. Do not commit, push, open a pull request, merge, release, or publish unless the owner explicitly requests that action.
