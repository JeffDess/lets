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

## Quickstart

1. Add `lets` as an input.
2. Define tasks in your project (and optionally reuse some [presets](#base-tasks)).
3. Build outputs with `mkOutputs`.
4. Add `mkLets` to your dev shell so `lets <task>` works (instead of `nix run #.<task> -- ...`).

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

      # Your project tasks (you can also import files instead, keep reading...)
      tasks = {
        greet = lets.mkTask {
          run = ''
            echo "Hello!"
          '';
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
$ nix develop
$ lets greet
# Hello!
```

### Demo task

The repo also includes a [`demo` task](tasks/demo/default.nix) you can run directly from the flake:

```bash
nix run github:JeffDess/lets demo
```

## Project Structure

The quickstart defined a tasks directly in the flake. While this could
work if you have very few tasks to run, there are better ways to
structure your project.

### Importing Tasks

The first option is an external file with multiple tasks in it.

Say you created `tasks.nix` next to you flake:

```text
.
├── flake.nix
└── tasks.nix
```

You can include it like this:

```nix
tasks = import ./tasks.nix { inherit pkgs; };
```

### Auto-discovery

As you project grows, you might want a more modular approach.
Breaking down each task in their own file keeps things tidy, but wiring each
task by hand can be tedious.

Enters auto-discovery: point `mkTasksFromDir` at a directory and every Nix file
in it automatically becomes a task.

```nix
tasks = lets.lib.${system}.mkTasksFromDir {
  inherit pkgs;
  dir = ./tasks; # or any directory in your project
};
```

Given this project structure:

```text
.
├── flake.nix
└── tasks/
   ├── lib/
   ├── test.nix
   └── release/
      ├── default.nix
      ├── changelog.tpl
      └── release.sh

```

It discovers both layouts:

* `<dir>/<name>.nix` — a single file
* `<dir>/<name>/default.nix` — a task directory (for tasks with their own scripts/fixtures)

So here `lets test` and `lets release` would be automatically wired.

Directories without a `default.nix` (e.g. a shared `tasks/lib/`) are ignored,
so you can keep helper scripts next to your tasks.
A single file may declare more than one task.

## Defining tasks

Tasks have those attributes:

| Attribute | Type | Required | Description |
| --- | --- | --- | --- |
| `description` | string | Yes | Shown in `lets help`. |
| `name` | string | No | The built binary (the command you run). Defaults to the attribute key. You rarely need to set it. |
| `runtimeInputs` | list of packages | No | Packages your task runs at runtime. Optional if no package is used in `run`, required for reproducibility.  |
| `run` | string | Yes | The implementation as an inline string or `builtins.readFile ./my-task.sh` to run an [external script](#external-scripts). |
| `flags` | attrset or list | No | CLI flags parsed and passed to `run` as variables. See the [declarative flags section](#declarative-flags). |

> [!IMPORTANT]
> Use underscores in task key/names when you want multi-word commands.
> So `lint_nix` will be called with `lets lint nix`
> Dashes stay literal inside each word, so `lint_nix-bash` will be called with `lets lint nix-bash`

## External scripts

Task execution can be:

* defined directly in Nix (`run = '' ... '';`)
* backed by shell scripts (`run = builtins.readFile ./scripts/my-task.sh;`)

Minimal task example with external script:

```nix
{ mkTask,...}:
{
  greet = mkTask {
    description = "Hello world";
    run = builtins.readFile ./scripts/greet.sh;
  };
}
```

## Declarative flags

While you could parse flags on your tasks as in any standard bash scripts,
`mkTask` allows to declare a `flags` attrset to automatically parse flags from
commands. Each flag name becomes a bash variable in `run`.

> [!NOTE]
> In popular usage, both flags and options are generally referred to as flags.
> Splitting them into option and flag lists would likely be confusing for some,
> so they're all are included in the `flags` list.
> In the documentation, _options_ will be referred to as `flag` and pure flags
> will be referred to as `boolean flag`.

### Simple flags

Adding only the long form of self explanatory flags is really simple:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    flags = [ "firstname" "lastname" ];
    run = ''
      echo "Hello $firstname $lastname"
    '';
  };
}
```

```bash
$ lets greet --firstname Foo --lastname Bar
# Hello Foo Bar
```

Order doesn't not matter, but flag names must match exactly.

### Parametrized flags

There's also another way of doing this if you want to unlock more options:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    flags = {
      name = {
        description = "Hello world with input and default value"; # Added to `lets help`
        short = "n";                    # Also accept -n as an alias to --name
        default = [ "$USER" "World" ];  # See Default section below
        required = true;                # Error if --name or -n is not provided
        type = "string";                # "string" (default) or "bool"
      };
    };
    run = ''
      echo "Hello $name"
    '';
  };
}
```

Then you'd get:

```bash
$ lets greet --name Foo
# Hello Foo

$ lets greet -n Foo
# Hello Foo

# If $USER is set to Foo
$ lets greet
# Hello Foo

# If $USER is unset
$ lets greet
# Hello World
```

> [!IMPORTANT]
> Underscores map to dashes in the long form, so a `dry_run` flag exposes
> `--dry-run` and the variable `$dry_run`.

#### Short form

You can add a shorthand for passing your flag, like `-n` for `--name` in the example.
`mkTask` validates the declaration at evaluation time and fails with a clear
message on a duplicate flag name, a duplicate `short`, a name that is not a bash
identifier, or a `short` that is not a single letter.

#### Default

A value is resolved as CLI argument first, then fallbacks to `default` value if
argument wasn't passed.
`default` is either a single value or a list of fallbacks.

* Literal: a plain string or any Nix value like `default = users.foo.name;`
* Environment variable: an element shaped like `"$VAR"` or `"${VAR}"`

Environment references are tried in the order listed, then the literal is the
final fallback, wherever you place it.

```nix
default = [ "$USERNAME" "$USER" "Foo" ];
default = [ "Foo" "$USERNAME" "$USER" ]; # literal position doesn't matter
```

To keep things understandable, stick with the real effective order.

#### Boolean flags

A `bool` flag takes no value: its presence sets the variable to `true` (default `false`).

#### Putting it together

You might have noticed that, since all flag parameters are optional, the first
form `flags = [ "name" ];` is short for `flags = { name = { }; }`.
An empty `{ }` definition is a plain `--name <value>` flag, so the two styles
can be mixed this way.

With that in mind, we could do something like:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with uppercase option";
    flags = {
      firstname = { default = "World"; };
      lastname = { };
      uppercase = { type = "bool"; };
    };
    run = ''
      msg="Hello $firstname''${lastname:+ $lastname!}"
      if [ "$uppercase" = true ]; then
        msg="''${msg^^}"
      fi
      echo "$msg"
    '';
  };
}
```

Result:

```bash
$ lets greet
# Hello World!

$ lets greet --firstname Foo
# Hello Foo!

$ lets greet --firstname Foo --uppercase
# HELLO FOO!

$ lets greet --firstname Foo --lastname Bar
# Hello Foo Bar!
```

## Task composition

A task can run another. Both styles use the injected `tasks` argument — the
fully-resolved set, so you can reach a task from **any** file (this is how you
compose across files, which `rec` can't do):

1) Put the other apps on `PATH` with `runtimeInputs` and call them by name.

```nix
{ tasks, mkTask, ... }:
{
  check = mkTask {
    description = "Run all checks";
    runtimeInputs = with tasks; [ lint_nix.app test.app ];
    run = ''
      lint_nix
      test
    '';
  };
}
```

1) Reference the other app's binary directly via `${tasks.<name>.app}/bin/<name>`.

```nix
{ tasks, mkTask, ... }:
{
  check = mkTask {
    description = "Run all checks";
    run = ''
      ${tasks.lint_nix.app}/bin/lint_nix
      ${tasks.test.app}/bin/test
    '';
  };
}
```

> [!NOTE]
> A task's binary is named after its file — `tasks/lint_nix.nix` builds
> `…/bin/lint_nix` — unless you set `name`, so the calls above just work. When a
> single file declares several tasks they share the file name; there, set `name`
> or resolve the binary with `lib.getExe` (`${lib.getExe tasks.lint_nix.app}`).
> The built-in `lint` (several tasks in one file) composes with `lib.getExe`.

## Base tasks

`mkTasks` ships with a small set of tasks you can reuse directly or compose in
your own tasks:

* `help` - Lists available tasks and their descriptions
  (auto-generated from your task set).
* `lint_bash` - Lints bash fragments embedded in Nix files and all `.sh` files
  using `shfmt` and `shellcheck`.
* `lint_nix` - Lints Nix files with `statix` and `deadnix`.
* `lint_nix-bash` - Lints just the bash fragments embedded in Nix files.
* `lint` - Runs all lint tasks in this flake
  (but you probably want to define your own).

The `help` command is included by default, the other tasks are completely
optional and can be added like this:

```nix
baseTasks = lets.lib.${system}.mkTasks { inherit pkgs; };

tasks = lets.lib.${system}.mkTasksFromDir {
  inherit (baseTasks) lint link_nix lint_bash lint_nix-bash;
  # ...
};
```

Or with external task file:

```nix
tasks = {
  inherit (baseTasks) lint_bash lint_nix;
} // import ./tasks.nix { inherit pkgs; };
```

Or with auto-discovery

```nix
baseTasks = lets.lib.${system}.mkTasks { inherit pkgs; };

tasks = lets.lib.${system}.mkTasksFromDir {
  inherit pkgs;
  dir = ./tasks;
  extraTasks = { inherit (baseTasks) lint lint_nix lint_bash lint_nix-bash; };
};
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

Refer to this project's [Github CI workflow](.github/workflows/ci.yml) as an example.

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
