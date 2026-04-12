# Tuna Control Protocol (TCP)

A cozy, abundance-driven game about raising thousands of animals in an abandoned datacenter. Built with Godot 4 and GDScript.

Players build interconnected infrastructure, animals arrive and thrive, and the game is about maximizing collective happiness. There is no lose condition. The challenge is finding the theoretical maximum — which is hard because animals have complex, interacting desires and emergent teaching behaviors.

## Prerequisites

- [Godot 4.3+](https://godotengine.org/download/) (GDScript, no C#)
- [Python 3](https://www.python.org/) (for linting tools)
- [gitleaks](https://github.com/gitleaks/gitleaks) (secret scanning)
- [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) (GDScript linter)
- [Git LFS](https://git-lfs.github.com/) (binary asset storage)

### macOS

```bash
brew install gitleaks
pip3 install gdtoolkit
```

### Linux

```bash
# gitleaks: download from https://github.com/gitleaks/gitleaks/releases
# or use your package manager
pip3 install gdtoolkit
```

## Setup

Clone the repo, set up LFS, and install git hooks:

```bash
git clone <repo-url>
cd tuna-control-protocol
git lfs install --force
git lfs pull
ln -sf ../../script/pre_commit .git/hooks/pre-commit
ln -sf ../../script/hooks/post-checkout .git/hooks/post-checkout
ln -sf ../../script/hooks/post-merge .git/hooks/post-merge
```

The `git lfs install --force` ensures LFS smudge/clean filters are active so binary assets (sprites, sounds) are checked out as real files, not LFS pointers. The post-checkout and post-merge hooks run `git lfs pull` automatically to prevent stale imports.

If Godot shows "Failed loading resource" errors after a pull or rebase, run:

```bash
script/fix-imports
```

Verify everything is working:

```bash
script/validate
```

You should see all checks pass. If `gitleaks` or `gdlint` isn't installed, the relevant check will tell you.

## Project Structure

```
.claude/
  agents/       AI agent definitions (dev team + player personas)
  rules/        Design and code rules (auto-loaded by Claude Code)
  skills/       Reusable skill definitions
schemas/        JSON schemas for game data (species, objects, behaviors)
script/
  checks/       Individual lint/validation checks
  pre_commit    Git pre-commit hook
  validate      Run all checks
```

Game code (when it exists) will follow the structure defined in `.claude/rules/file-structure.md`:

```
engine/         Framework code (core logic, desires, spatial, animals, network, save, mod)
nodes/          Thin Godot wrappers (rendering, input, HUD, camera)
mods/tcp_base/  The base game (ships as a mod)
tests/          All tests (unit, integration, scenario, snapshot, soak, perf)
```

## Checks

All checks live in `script/checks/` and can be run individually or together:

| Check | What it does |
|---|---|
| `gdlint` | GDScript style enforcement via `.gdlintrc` |
| `no_parent_paths` | No `../` paths in GDScript (children never reach up) |
| `no_node_in_core` | No `Node` imports in `engine/` (pure core pattern) |
| `validate_json` | JSON/JSONC syntax validation |
| `json_snake_case_keys` | All JSON keys must be `snake_case` |
| `entity_id_prefix` | Entity IDs must use `mod_id:entity_id` format |
| `no_secrets` | Secret/credential scanning via [gitleaks](https://github.com/gitleaks/gitleaks) |

Run all checks: `script/validate`

Run one check: `script/validate no_secrets`

The pre-commit hook runs the relevant subset on staged files only.

## Design Docs

- `CLAUDE.md` — Project overview, design philosophy, rules index (also serves as AI agent context)
- `PLANNING.md` — Detailed design decisions, prototype spec, open questions
- `.claude/rules/` — Authoritative rules for code style, architecture, systems design

## Contributing

1. Read `.claude/rules/` before writing code — especially `design-philosophy.md` and `code-style.md`.
2. All game logic goes in `engine/` as `RefCounted` or `Resource` classes. No game logic in `Node` subclasses.
3. All game values use integers (0-1000 scale). Floats only at the rendering boundary.
4. Every tunable number comes from config JSON, not code.
5. Run `script/validate` before committing. The pre-commit hook will catch most issues, but the full suite catches more.

## License

TBD
