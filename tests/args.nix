{ pkgs }:
let
  inherit (pkgs) lib;
  args = import ../lib/args.nix { inherit lib; };
in
{
  ### Normalisation ###

  testNormalizeListToEmptySpecs = {
    expr = args.normalize [ "foo" ];
    expected = {
      foo = { };
    };
  };

  testNormalizeAttrsPassthrough = {
    expr = args.normalize { a.short = "a"; };
    expected = {
      a.short = "a";
    };
  };

  ### Classification ###

  testIsOptionByDefault = {
    expr = args.isOption { };
    expected = true;
  };

  testIsFlag = {
    expr = args.isFlag { type = "flag"; };
    expected = true;
  };

  testIsPositional = {
    expr = args.isPositional { type = "positional"; };
    expected = true;
  };

  testLongOfKebabCases = {
    expr = args.longOf "dry_run";
    expected = "--dry-run";
  };

  ### Grouping ###

  testSplitGroupsAndOrders = {
    expr = args.split {
      verbose.type = "flag";
      name = { };
      src = {
        type = "positional";
        index = 2;
      };
      dst = {
        type = "positional";
        index = 1;
      };
    };
    expected = {
      optNames = [ "name" ];
      flagNames = [ "verbose" ];
      posNames = [
        "dst"
        "src"
      ];
    };
  };
}
