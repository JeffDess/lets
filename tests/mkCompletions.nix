{ pkgs }:
let
  inherit (pkgs) lib;
  mkCompletions = import ../lib/mkCompletions.nix { inherit pkgs; };
  inherit (import ./fixture.nix { inherit pkgs; }) tasks;

  m = (mkCompletions { inherit tasks; }).model;
  longsAt = path: map (o: o.long) (m.options path);
in
{
  ### Tree navigation ###

  # Top-level words
  testTopWordsSorted = {
    expr = m.subWords [ ];
    expected = [
      "demo"
      "help"
      "lint"
      "show"
      "version"
    ];
  };

  # A namespace prefix lists its children, keeping hyphens intact.
  testLintChildren = {
    expr = m.subWords [ "lint" ];
    expected = [
      "nix"
      "nix-bash"
    ];
  };

  # A leaf task has no subcommand children.
  testVersionNoChildren = {
    expr = m.subWords [ "version" ];
    expected = [ ];
  };

  # Unknown path yields nothing.
  testUnknownPathNoChildren = {
    expr = m.subWords [
      "lint"
      "bogus"
    ];
    expected = [ ];
  };

  ### Command resolution ###

  # A prefix that is also a runnable task.
  testLintIsCommand = {
    expr = m.isCommand [ "lint" ];
    expected = true;
  };

  # Multi-word leaf with a hyphen resolves.
  testLintNixBashIsCommand = {
    expr = m.isCommand [
      "lint"
      "nix-bash"
    ];
    expected = true;
  };

  testUnknownIsNotCommand = {
    expr = m.isCommand [
      "lint"
      "bogus"
    ];
    expected = false;
  };

  ### Options & flags ###

  testVersionFlagLong = {
    expr = longsAt [ "version" ];
    expected = [ "--dry-run" ];
  };

  # A node can be both a namespace parent and carry its own options.
  testLintParentHasOptions = {
    expr = map (o: {
      inherit (o) long short;
    }) (m.options [ "lint" ]);
    expected = [
      {
        long = "--verbose";
        short = "v";
      }
    ];
  };

  testVersionFlagDoesNotTakeValue = {
    expr = (lib.head (m.options [ "version" ])).takesValue;
    expected = false;
  };

  testDemoOptionLongAndShort = {
    expr = map (o: {
      inherit (o) long short takesValue;
    }) (m.options [ "demo" ]);
    expected = [
      {
        long = "--locale";
        short = "l";
        takesValue = true;
      }
    ];
  };

  # Positionals are not reported as options.
  testDemoPositionalNotAnOption = {
    expr = builtins.elem "--name" (longsAt [ "demo" ]);
    expected = false;
  };

  testDemoPositionalName = {
    expr = map (p: p.name) (m.positionals [ "demo" ]);
    expected = [ "name" ];
  };

  ### Builtins ###

  testHelpTaskOption = {
    expr = longsAt [ "help" ];
    expected = [ "--task" ];
  };

  # `lets show <TAB>` and `lets help -t <TAB>` offer the task names.
  testShowTaskChoices = {
    expr = (lib.head (m.positionals [ "show" ])).choices;
    expected = [
      "demo"
      "lint"
      "lint_nix"
      "lint_nix-bash"
      "version"
    ];
  };

  testHelpTaskOptionChoices = {
    expr = (lib.head (m.options [ "help" ])).choices;
    expected = [
      "demo"
      "lint"
      "lint_nix"
      "lint_nix-bash"
      "version"
    ];
  };

  # `lets -c <TAB>` / `lets --completions <TAB>` offers shell choices as the
  # value of the root -c/--completions option.
  testRootCompletionsOption = {
    expr =
      let
        o = lib.head (builtins.filter (o: o.long == "--completions") (m.options [ ]));
      in
      {
        inherit (o) short takesValue choices;
      };
    expected = {
      short = "c";
      takesValue = true;
      choices = [
        "bash"
        "fish"
        "nushell"
        "zsh"
      ];
    };
  };
}
