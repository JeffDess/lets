# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-06-29

### Features

- Add release and version tasks and flow
- Syntax highlighting for version and relase output preview
- Add test task
- Add log helper functions
- Add shell completions
- Simplified setup with mkFlake
- Simplified baseTasks composition
- Remove builtin subcommands to standardize root API
- Format error output from builtins

### Bug Fixes

- Wrong positional argument indentation in help output
- Mute Rust info and warn logs in version and release output
- Devshell is composed correctly

### Performance

- Dedup extra nixpkgs of pre-commit-hooks

### Documentation

- Add complete standalone files for backing up examples in README
- Detail composable task library pattern
- Better flake composability instructions
- Rewrite of README intro

## [0.0.1] - 2026-06-24

### Features

- Initial commit
- Use underscore as task_type separator instead of dash
- Auto-discovery of tasks
- Add declarative flags
- [**breaking**] Rename flags -> args in task params
- [**breaking**] Support positional arguments
- Add text formating
- Add editorconfig config + hook/task/ci
- Add --task option in help
- Add show command
- Alias help subcommand with -h/--help flag
- Alias show subcommand with -s/--show flag
- Add project versioning & version flag

### Bug Fixes

- Mute dirty git warning
- Add shellcheck hint in .envrc
- Hello pkg is required in flake check
- Don't crash commands because of shellcheck failures
- --task=... isn't recognized as option

### Documentation

- Add CI examples and tips in readme
- Add missing "app" in task references
- More simple quickstart
- Restructure readme for better progressive disclosure
- Add editor support section and bash injection in task.run
- Mention support for inline arguments
