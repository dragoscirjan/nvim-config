# Contributing

This repository is a personal Neovim configuration based on LazyVim. This guide applies to human contributors and coding agents.

Read this document before planning or performing an architecture, implementation, documentation, configuration, policy, or publication change.

## Contribution workflow

1. Clarify ambiguous requirements and confirm shared understanding.
2. Keep each change focused on one request or task.
3. Follow the isolated-workspace gate and configuration in `AGENTS.md` before changing repository state.
4. Preserve existing behavior outside the approved scope.
5. Update documentation when setup, behavior, or maintenance steps change.
6. Read and follow `VALIDATION.md` before validation or any requested publication action.
7. Do not commit, push, open a pull request, merge, release, or publish unless the owner explicitly requests that action.

## Repository structure

- Keep `init.lua` as the small entry point that loads `config.lazy`.
- Put Neovim options, keymaps, and autocommands under `lua/config/`.
- Put custom plugin specifications under `lua/plugins/`.
- Manage LazyVim extras through `lazyvim.json` when an existing extra provides the required behavior.
- Follow `stylua.toml` for Lua formatting.
- Preserve declared interpreter contracts and platform guards in Bash and PowerShell scripts.
- Do not run `whisper-install.sh`, `whisper-test.sh`, or `Build-LuaTiktoken.ps1` merely to inspect or classify the repository.
- Avoid broad plugin updates, generated lock-state changes, or unrelated formatting unless the task requires them.

## Instruction maintenance

When repository instructions no longer fit an observed workflow, follow `.agents/skills/instruction-maintenance/SKILL.md`. An agent may perform a read-only audit and present an exact proposal. It must not mutate instruction files until the owner approves that exact proposal.

Changed evidence, scope, dependencies, handoffs, or protected rules require a revised proposal and new approval.

## Environment and dependencies

This repository defines no required project environment variables.

Some optional scripts depend on user-level tools, system packages, network access, and paths under `$HOME`. Treat those as explicit runtime prerequisites. Do not install, remove, or reconfigure user-level tools or system packages without approval.

Do not fetch or execute plugins or external source code merely to inspect the configuration.

## Publication report

Before any explicitly requested commit, push, pull request, merge, release, or publication action, report:

- changed files
- checks that passed
- checks that failed
- checks that did not run and why
- remaining risks or follow-up work

The owner decides whether repository history or remote state may change.
