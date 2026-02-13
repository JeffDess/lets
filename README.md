# lets - A Nix Task Runner

![lets do it!](img/tagline.png)
> [!WARNING]
> 🚧 This project is under active development 🚧
>
> While it is ready to use in its current form, it is still in an experimental phase.
> Use at your own risk and expect things to break.

A simple task runner that combines the power of Nix and Bash.

## Goals

This project aims for:

* [ ] Reusable tasks across CLI, editor, git hooks and CI
* [ ] Reproducible outcome on any environment
* [ ] Support for task composition
* [ ] Modularity: splitting files into smaller manageable units
* [ ] Automated quality checks
* [ ] Reduce duplication across projects
* [ ] Modern tooling: good linter, formatter and LSP
* [ ] Language/Framework/Tool agnostic. Use the same tool on any project
* [ ] Performant and easy to use

## Requirements

* [Nix](https://nixos.org/download/) with [flakes](https://wiki.nixos.org/wiki/Flakes) enabled (`nix-command` + `flakes`)

## Quickstart (integrate into your flake)

1. Add `lets` as an input.
2. Define tasks in your project (and optionally reuse some from `mkTasks`).
3. Build outputs with `mkOutputs`.
4. Add `mkLets` to your dev shell so `lets <task>` works.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    lets.url = "github:JeffDess/lets";
  };

  outputs = { nixpkgs, lets, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Optional: reuse upstream tasks
      baseTasks = lets.lib.${system}.mkTasks { inherit pkgs; };

      # Your project tasks
      tasks = {
        inherit (baseTasks) lint-bash lint-nix;
        lint-js = {
          description = "Lint JavaScript";
          app = pkgs.writeShellApplication {
            name = "lint-js";
            runtimeInputs = [ pkgs.nodejs pkgs.nodePackages.eslint ];
            text = "eslint .";
          };
        };
      };

      taskOutputs = lets.lib.${system}.mkOutputs { inherit pkgs tasks; };
      letsCmd = lets.lib.${system}.mkLets { inherit pkgs; };
    in
    {
      apps.${system} = taskOutputs.apps;
      devShells.${system}.default = pkgs.mkShell { packages = [ letsCmd ]; };
    };
}
```

Then in your project:

```bash
nix develop
lets help
lets lint bash
lets lint nix
lets lint js
```

## Base tasks

`mkTasks` ships with a small set of tasks you can reuse directly or compose in your own tasks:

* `help` - Lists available tasks and their descriptions (auto-generated from your task set).
* `lint-bash` - Lints bash fragments embedded in Nix files and all `.sh` files using `shfmt` and `shellcheck`.
* `lint-nix` - Lints Nix files with `statix` and `deadnix`.
* `lint` - Runs all lint tasks in this flake (but you probably want to define your own).

## Demo task (from the flake)

The repo includes a [`demo` task](tasks/demo.nix) you can run directly from the flake:

```bash
nix run github:JeffDess/lets demo
```

## Defining tasks

Each task is an attribute with:

* `description` (shown in `lets help`)
* `app` (usually from `pkgs.writeShellApplication`)
  * `name` will be used for invoking it.
  * `runtimeInputs` must include packages you run in your task
  * `text` is the actual implementation

> [!IMPORTANT]
> Hyphens in app name are used for splitting subcommands.
> So `lint-nix` will be called with `lets lint nix`

Tasks can be:

* defined directly in Nix (`text = '' ... '';`)
* backed by shell scripts (`text = builtins.readFile ./scripts/my-task.sh;`)

Minimal task example:

```nix
{
  lint-js = {
    description = "Lint JavaScript";
    app = pkgs.writeShellApplication {
      name = "lint-js";
      runtimeInputs = [ pkgs.nodejs pkgs.nodePackages.eslint ];
      text = builtins.readFile ./scripts/lint-js.sh;
    };
  };
}
```

You can also pass flags in `lets` commands:

```bash
lets lint js --files=index.js
# OR
lets lint js --files index.js
# OR
lets lint js -f index.js
```

They will be passed on to your tasks.
It's up to you to parse it in your implementation, as you would on a regular bash script.

## Task composition

You can compose tasks in two ways:

1) Add the other task app to `runtimeInputs` and call it by name.

```nix
{
  lint = {
    description = "Lint all";
    app = pkgs.writeShellApplication {
      name = "lint";
      runtimeInputs = [ tasks.lint-js tasks.lint-nix ];
      text = ''
        lint-js
        lint-nix
      '';
    };
  };
}
```

1) Call the other task app directly via `${task}/bin/<name>`.

```nix
{
  lint = {
    description = "Lint all";
    app = pkgs.writeShellApplication {
      name = "lint";
      text = ''
        ${tasks.lint-js}/bin/lint-js
        ${tasks.lint-nix}/bin/lint-nix
      '';
    };
  };
}
```

## CI integration

If you wish to run a task in CI, you can just run it from the flake. It will
use the exact same packages as on your local dev shell.

### GitHub Actions

```yaml
name: CI
on:
  push:
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v21
      - uses: DeterminateSystems/magic-nix-cache-action@v13
      - name: Run lint task
        run: nix run .#lint
```

### GitLab CI

```yaml
variables:
  NIX_CONFIG: "experimental-features = nix-command flakes"

lint:
  stage: lint
  script:
    - nix run .#lint
```

## Task organization strategies

You can organize tasks in several ways. You can start small and expands as you
add more tasks.

Here are some ideas:

### 1) Keep tasks in `flake.nix` (really small projects)

```text
.
├── flake.nix
└── scripts/
   └── lint-js.sh
```

### 2) Put all tasks in one `tasks.nix` (simple tasks)

```text
.
├── flake.nix
├── tasks.nix
└── scripts/
   ├── lint-js.sh
   └── test.sh
```

### 3) Use `tasks/default.nix` importing one file per task

```text
.
├── flake.nix
├── tasks/
│  ├── default.nix
│  ├── lint-js.nix
│  ├── test.nix
│  └── build.nix
└── scripts/
   ├── lint-js.sh
   └── test.sh
```

### 4) Use task directories (`tasks/<taskName>/default.nix`)

Useful when each task has its own script, config, or fixtures.

```text
.
├── flake.nix
├── tasks/
│  ├── default.nix
│  ├── lint-js/
│  │  ├── default.nix
│  │  └── lint-js.sh
│  ├── test/
│  │  ├── default.nix
│  │  └── test.sh
│  └── release/
│     ├── default.nix
│     ├── changelog.tpl
│     └── release.sh
└── scripts/
   └── shared-lib.sh
```
