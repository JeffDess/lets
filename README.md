# lets - A Nix Task Runner

![lets do it!](img/tagline.png)
> [!WARNING]
> 🚧 This project is under active development 🚧
>
> While it is ready to use in its current form, it is still in an
> experimental phase.
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

* [Nix](https://nixos.org/download/) with
  [flakes](https://wiki.nixos.org/wiki/Flakes) enabled
  (`nix-command` + `flakes`)

## Quickstart

1. Add `lets` as an input.
2. Define tasks in your project (and optionally reuse some
   [presets](#base-tasks)).
3. Build outputs with `mkOutputs`.
4. Add `mkLets` to your dev shell so `lets <task>` works (instead of
   `nix run #.<task> -- ...`).

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
      inherit (lets.lib.${system}) mkTasks mkOutputs mkLets;
      mkTask = lets.lib.${system}.mkTask { inherit pkgs; };

      # Your project tasks (you can also import files instead, keep reading...).
      tasks = mkTasks {
        greet = mkTask {
          description = "Say hello";
          run = ''
            echo "Hello!"
          '';
        };
      };

      taskOutputs = mkOutputs { inherit pkgs tasks; };
      letsCmd = mkLets { inherit pkgs tasks; };
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

### Usage

```text
lets <task>                     # Run task
lets -h / --help / help         # Display help and list available tasks
lets -s / --show / show <task>  # Display task details
lets -v / --version             # Display version
```

### Demo task

The repo also includes a [`demo` task](tasks/demo/default.nix) you can
run directly from the flake:

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
tasks = mkTasks (import ./tasks.nix { inherit pkgs mkTask; });
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
* `<dir>/<name>/default.nix` — a task directory (for tasks with their
  own scripts/fixtures)

So here `lets test` and `lets release` would be automatically wired.

Directories without a `default.nix` (e.g. a shared `tasks/lib/`) are ignored,
so you can keep helper scripts next to your tasks.
A single file may declare more than one task.

## Defining tasks

Tasks have those attributes:

<!-- editorconfig-checker-disable -->
| Attribute | Type | Required | Description |
| --- | --- | --- | --- |
| `description` | string | Yes | Shown in `lets help`. |
| `name` | string | No | The built binary (the command you run). Defaults to the attribute key. You rarely need to set it. |
| `runtimeInputs` | list of packages | No | Packages your task runs at runtime. Optional if no package is used in `run`, required for reproducibility.  |
| `run` | string | Yes | The implementation as an inline string or `builtins.readFile ./my-task.sh` to run an [external script](#external-scripts). |
| `args` | attrset or list | No | CLI arguments (options, flags and positionals) parsed and passed to `run` as variables. See the [declarative arguments section](#declarative-arguments). |
<!-- editorconfig-checker-enable -->

> [!IMPORTANT]
> Use underscores in task key/names when you want multi-word commands.
> So `lint_nix` will be called with `lets lint nix`
> Dashes stay literal inside each word, so `lint_nix-bash` will be
> called with `lets lint nix-bash`

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

## Text formatting

Every task's `run` gets a small ANSI formatting toolkit injected automatically.
It comes in three flavors:

```bash
# Constants (uppercase):
echo "${BOLD}Hello${RESET} ${BLUE}World${RESET}!"

# Functions (lowercase):
green "✅ done"
bold "Important"

# Merged style + color (<style>_<color>):
bold_blue "Heading"
underline_red "Error"
```

Available names:

| Kind | Names |
| --- | --- |
| Colors | `black` `red` `green` `yellow` `blue` `magenta` `cyan` `white` |
| Styles | `bold` `dim` `italic` `underline` |

* **Functions** (lowercase) exist for every color and style. They print the text
  formatted, followed by a newline (like `echo`), and
  **already append the reset**
  — so `blue "hi"` closes itself and there is no `reset` function to call.
* **Merged functions** combine any style with any color as `<style>_<color>`
  (e.g. `bold_green`, `dim_cyan`, `underline_yellow`).
* **Constants** (uppercase: `RED`, `BOLD`, …) exist for the same names. Use them
  when you assemble strings yourself — then you must close the sequence with the
  `RESET` constant: `echo "${BLUE}hi${RESET}"`. `RESET` exists only as
  a constant, for this manual form.

### Color detection

Formatting is emitted only when it makes sense, following the common
conventions:

* **disabled** when stdout is not a terminal (piped or redirected), so logs and
  captured output stay clean;
* **disabled** when `NO_COLOR` is set to a non-empty
  value (takes precedence);
* **forced on** when `FORCE_COLOR` is set — handy to keep colors through a pipe
  or in tests.

When formatting is off, both the constants and the functions degrade gracefully:
constants become empty strings and functions print plain text.

> [!IMPORTANT]
> These names are **reserved** in every task's `run`: the constants and
> functions listed above. Avoid redefining them in your scripts.

Here's a minimal example:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world in color";
    run = ''
      bold_blue "Hello, World!"
    '';
  };
}
```

```bash
$ lets greet
# Hello, World! (bold blue on a terminal)

$ lets greet | cat
# Hello, World!  (plain text when piped)
```

## Declarative arguments

While you could parse arguments in your tasks as in any standard bash script,
`mkTask` lets you declare an `args` attrset to automatically parse them from the
command line. Each argument name becomes a bash variable in `run`.

> [!NOTE]
> A _declarative argument_ is one of:
>
> * an _option_, which takes a value (`--name Foo`)
> * a _flag_, which is a boolean toggle (`--dry-run`)
> * a _positional_, bound by its position on the received command
>
> The `type` attribute picks which one you get (`option` by default).

### Simple arguments

Adding only the long form of self explanatory options is really simple.
By default, arguments are long form options:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    args = [ "firstname" "lastname" ];
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

Order does not matter, but argument names must match exactly.

### Parametrized arguments

There's also another way of doing this if you want to unlock more options:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    args = {
      name = {
        # Added to `lets help`
        description = "Hello world with input and default value";
        # Accept -n as an alias to --name
        short = "n";
        # See Default section below
        default = [ "$USER" "World" ];
        # Error if --name or -n is not provided
        required = true;
        # "option" (default), "flag" or "positional"
        type = "option";
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
> Underscores map to dashes in the long form, so a `dry_run` argument exposes
> `--dry-run` and the variable `$dry_run`.

#### Short form

You can add a shorthand for passing your argument, like `-n` for `--name` in
the example. `mkTask` validates the declaration at evaluation time and fails
with a clear message on a duplicate argument name, a duplicate `short`, a name
that is not a bash identifier, or a `short` that is not a single letter.

#### Inline value

An option's value can be passed as a separate word (`--name Foo`) or attached to
the long form with an `=` — the _inline value_ form:

```bash
$ lets greet --name=Foo
# Hello Foo
```

Short forms always take their value as the next word (`-n Foo`).

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

#### Flags

A `flag` (`type = "flag"`) takes no value: its presence sets the variable to
`true` (default `false`).

#### Positional arguments

A `positional` is bound by its place on the command line rather than by a
`--name`, using a 1-based `index` (index 0 is the command itself). It supports
`default` and `required` like an option, but not `short`, and indices must be
contiguous starting at 1.

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with positional arguments";
    args = {
      name = { type = "positional"; index = 1; required = true; };
    };
    run = ''
      echo "Hello $name (the rest stays in $@: $*)"
    '';
  };
}
```

Options and flags are parsed first, then the leftover words fill the positionals
in index order. Anything past the declared positionals stays in `$@`:

```bash
$ lets greet Foo Bar
# Hello Foo (the rest stays in $@: Bar)

$ lets greet -- Foo Bar # This is safer, no possible collision with sub-commands
# Hello Foo (the rest stays in $@: Bar)
```

> [!NOTE]
> `lets` finds where the (sub-)command name ends by matching the longest run of
> leading words against your task names, so `lets fmt flake.nix` runs the `fmt`
> task with `flake.nix` as a positional. For this to work, pass your tasks to
> `mkLets` (`mkLets { inherit pkgs tasks; }`). Use `--` to force a word to be an
> argument (`lets fmt -- nix`, even if a `fmt_nix` task exists). Options must
> come before positionals.

#### Putting it together

You might have noticed that, since all argument parameters are optional, the
first form `args = [ "name" ];` is short for `args = { name = { }; }`.
An empty `{ }` definition is a plain `--name <value>` option, so the two styles
can be mixed this way.

With that in mind, we could do something like:

```nix
{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with uppercase option";
    args = {
      firstname = { default = "World"; };
      lastname = { }; # same as `lastname = { type = "option"; };`
      uppercase = { type = "flag"; };
    };
    run = ''
      msg="Hello $firstname''${lastname:+ $lastname}!"
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

A task can run another. Reach the other task through the injected `tasks`
argument — the fully-resolved set, so you can compose across **any** file.
You might use other Nix features to achieve this, but this supported form
works everywhere:

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

> [!NOTE]
> A task's binary is named after the **attribute key** it is bound under (e.g.
> `lint_nix = mkTask { … }` builds `.../bin/lint_nix`), even when one file
> declares several tasks. Set `name` only when you want the command to differ
> from the key.

## Base tasks

`lets` ships with a small set of tasks you can reuse directly or compose in
your own tasks (build the set with `mkBaseTasks`):

* `help` - Lists available tasks and their descriptions
  (auto-generated from your task set). Pass `-t <task>` (or
  `--task <task>`) to print just that task's usage, e.g.
  `lets help -t lint_nix`. `lets --help` and `lets -h` are
  aliases for `lets help`.
* `show <task>` - Prints a single task's usage, the packages it pulls in
  (its `runtimeInputs`) and its script with syntax highlighting, e.g.
  `lets show lint_nix`. `lets --show <task>` and `lets -s <task>` are
  aliases for `lets show <task>`.
* `lint_bash` - Lints bash fragments embedded in Nix files and all `.sh` files
  using `shfmt` and `shellcheck`.
* `lint_nix` - Lints Nix files with `statix` and `deadnix`.
* `lint_nix-bash` - Lints just the bash fragments embedded in Nix files.
* `lint` - Runs all lint tasks in this flake
  (but you probably want to define your own).

The `help` and `show` commands are included by default, the other tasks are
completely optional. Build the base set with `mkBaseTasks` and cherry-pick
from it:

```nix
baseTasks = lets.lib.${system}.mkBaseTasks { inherit pkgs; };

tasks = lets.lib.${system}.mkTasksFromDir {
  inherit pkgs;
  dir = ./tasks;
  extraTasks = { inherit (baseTasks) lint_bash lint_nix; };
};
```

Or merged with an external task file:

```nix
baseTasks = lets.lib.${system}.mkBaseTasks { inherit pkgs; };

tasks = mkTasks (
  { inherit (baseTasks) lint_bash lint_nix; }
  // import ./tasks.nix { inherit pkgs mkTask; }
);
```

## Editor Support

Since this project is largely built with Nix and Bash, most editors will support
those filetypes out of the box.

An exception to that is the `run` task attribute, which embeds Bash syntax
inside a Nix file. Editors backed by the tree-sitter grammar only inject
Bash highlighting (and LSP features, through tools like
[otter.nvim](https://github.com/jmbuhr/otter.nvim)) for a fixed set of attribute
names. `run` is not one of them, so it stays unhighlighted by default.

In Neovim, add an injection query so tree-sitter treats `run` as Bash. Create
`~/.config/nvim/after/queries/nix/injections.scm`:

```scheme
;extends

; lets: inject Bash into the task `run` attribute
(binding
  attrpath: (attrpath (identifier) @_path)
  expression: [
    (string_expression
      ((string_fragment) @injection.content
        (#set! injection.language "bash")))
    (indented_string_expression
      ((string_fragment) @injection.content
        (#set! injection.language "bash")))
  ]
  (#eq? @_path "run")
  (#set! injection.combined))
```

The `;extends` directive keeps the grammar's built-in injections and only adds
the `run` attribute on top. For a one-off string without any setup, prefix it
with a language hint instead: `run = /* bash */ ''…'';`.

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

Refer to this project's [Github CI workflow](.github/workflows/ci.yml)
as an example.

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
