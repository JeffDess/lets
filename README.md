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
2. Define tasks in your project (and optionally reuse some presets).
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

      # Your project tasks (see auto-discovery for an alternative approach)
      tasks = {
        inherit (baseTasks) lint_bash lint_nix; # Optional
        # Example of inline task
        lint_js = {
          description = "Lint JavaScript";
          app = pkgs.writeShellApplication {
            name = "lint_js";
            runtimeInputs = with pkgs; [ nodejs nodePackages.eslint ];
            text = "eslint .";
          };
        };
      } // import ./tasks.nix { inherit pkgs; }; # Optional, for external task definitions

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

### Auto-discovery

Instead of including tasks in your flake or wiring each task by hand,
point `mkTasksFromDir` at a directory and every nix file in it becomes a task
automatically.

```nix
tasks = lets.lib.${system}.mkTasksFromDir {
  inherit pkgs;
  dir = ./tasks; # or any directory in your project
  extraTasks = { inherit (baseTasks) lint_bash lint_nix lint; }; # Optional
};
```

It discovers both layouts:

* `<dir>/<name>.nix` — a single file
* `<dir>/<name>/default.nix` — a task directory (for tasks with their own scripts/fixtures)

Directories without a `default.nix` (e.g. a shared `tasks/lib/`) are ignored,
so you can keep helper scripts next to your tasks.

Each task file receives `{ pkgs, tasks, ... }` and returns an attrset of tasks.
The `tasks` argument is the fully-resolved set, so a task can reference another
(e.g. `tasks.lint_nix.app`). A single file may declare more than one task.

## Base tasks

`mkTasks` ships with a small set of tasks you can reuse directly or compose in your own tasks:

* `help` - Lists available tasks and their descriptions (auto-generated from your task set).
* `lint_bash` - Lints bash fragments embedded in Nix files and all `.sh` files using `shfmt` and `shellcheck`.
* `lint_nix` - Lints Nix files with `statix` and `deadnix`.
* `lint` - Runs all lint tasks in this flake (but you probably want to define your own).

## Demo task (from the flake)

The repo includes a [`demo` task](tasks/demo/default.nix) you can run directly from the flake:

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
> Use underscores in task names when you want multi-word commands.
> So `lint_nix` will be called with `lets lint nix`
> Dashes stay literal inside each word, so `lint_nix-bash` will be called with `lets lint nix-bash`

Tasks can be:

* defined directly in Nix (`text = '' ... '';`)
* backed by shell scripts (`text = builtins.readFile ./scripts/my-task.sh;`)

Minimal task example:

```nix
{
  lint_js = {
    description = "Lint JavaScript";
    app = pkgs.writeShellApplication {
      name = "lint_js";
      runtimeInputs = with pkgs; [ nodejs nodePackages.eslint ];
      text = builtins.readFile ./scripts/lint_js.sh;
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
      runtimeInputs = [ tasks.lint_js tasks.lint_nix ];
      text = ''
        lint_js
        lint_nix
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
        ${tasks.lint_js}/bin/lint_js
        ${tasks.lint_nix}/bin/lint_nix
      '';
    };
  };
}
```

## CI integration

If you wish to run a task in CI, you can just run it from the flake. It will
use the exact same packages as on your local dev shell.

It's important to use `nix run` and not `nix shell` or `nix develop`, as the
latter would install extra packages that aren't needed to run the tasks.

### GitHub Actions

```yaml
env:
  NIX_CONFIG: experimental-features = nix-command flakes

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

You can see an example in the [Github CI workflow](.github/workflows/ci.yml) of this project.

### GitLab CI

> [!TIP]
> Use a self-hosted NixOS shell executor for blazingly fast job runs

```yaml
variables:
  NIX_CONFIG: experimental-features = nix-command flakes

lint:
  stage: lint
  script:
    - nix run .#lint

```

You can see a complete file in the [Gitlab CI Pipeline example](.gitlab-ci.yml).

## Task organization strategies

You can organize tasks in several ways.
You can start small and expands as you add more tasks.

Here are some ideas:

### 1) Keep tasks in `flake.nix` (really small projects)

Everything is self-contained in your flake:

```text
.
├── flake.nix
└── scripts/
   └── lint_js.sh
```

### 2) Put all tasks in one `tasks.nix` (simple tasks)

Import an external file containing all of your tasks:

```text
.
├── flake.nix
├── tasks.nix
└── scripts/
   ├── lint_js.sh
   └── test.sh
```

For this pattern, you can include it like:

```nix
tasks = import ./tasks.nix { inherit pkgs; };
```

Or, with base tasks:

```nix
tasks = {
  inherit (baseTasks) lint_bash lint_nix;
} // import ./tasks.nix { inherit pkgs; };
```

### 3) One file per task in `tasks/`

```text
.
├── flake.nix
└── tasks/
   ├── lib/
   │  ├── lint_js.sh
   │  └── test.sh
   ├── lint_js.nix
   ├── test.nix
   └── build.nix
```

Auto-discovered with [`mkTasksFromDir`](#auto-discovery):

```nix
tasks = lets.lib.${system}.mkTasksFromDir {
  inherit pkgs;
  dir = ./tasks;
  extraTasks = { inherit (baseTasks) lint_bash; }; # Optional
};
```

### 4) Use task directories (`tasks/<taskName>/default.nix`)

Useful when each task has its own script, config, or fixtures.
Also auto-discovered with [`mkTasksFromDir`](#auto-discovery).

```text
.
├── flake.nix
├── tasks/
│  ├── lint_js/
│  │  ├── default.nix
│  │  └── lint_js.sh
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

With auto-discovery, you could easily mix #3 and #4.
