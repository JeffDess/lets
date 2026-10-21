{ pkgs }:
let
  inherit (pkgs) lib;
  validate = import ../../lib/validate.nix { inherit lib; };
  args = import ../../lib/args.nix { inherit lib; };
  errs =
    rawArgs:
    validate {
      inherit rawArgs;
      normArgs = args.normalize rawArgs;
    };
in
{
  ### Aliases ###

  testAliasesValid = {
    expr = errs { url.aliases.docs = "https://example.com/docs"; };
    expected = [ ];
  };

  testRejectAliasesOnFlag = {
    expr = errs {
      verbose = {
        type = "flag";
        aliases.on = "true";
      };
    };
    expected = [ "aliases must be an attribute set of strings on options or positionals: verbose" ];
  };

  testRejectAliasesList = {
    expr = errs { url.aliases = [ "docs" ]; };
    expected = [ "aliases must be an attribute set of strings on options or positionals: url" ];
  };

  testRejectAliasNonString = {
    expr = errs { url.aliases.docs = 42; };
    expected = [ "aliases must be an attribute set of strings on options or positionals: url" ];
  };

  testRejectAliasEmptyName = {
    expr = errs { url.aliases."" = "https://example.com"; };
    expected = [ "alias names must be non-empty and, on positionals, not start with '-': url" ];
  };

  testRejectPositionalAliasDashName = {
    expr = errs {
      url = {
        type = "positional";
        index = 1;
        aliases."-d" = "https://example.com/docs";
      };
    };
    expected = [ "alias names must be non-empty and, on positionals, not start with '-': url" ];
  };

  testOptionAliasDashName = {
    expr = errs { url.aliases."-d" = "https://example.com/docs"; };
    expected = [ ];
  };

  ### Accepts valid shapes ###

  testValidEmpty = {
    expr = errs { };
    expected = [ ];
  };

  testValidOptionWithShort = {
    expr = errs { name.short = "n"; };
    expected = [ ];
  };

  testValidContiguousPositionals = {
    expr = errs {
      src = {
        type = "positional";
        index = 1;
      };
      dst = {
        type = "positional";
        index = 2;
      };
    };
    expected = [ ];
  };

  ### Rejects invalid shapes ###

  testRejectDuplicateShort = {
    expr = errs {
      a.short = "x";
      b.short = "x";
    };
    expected = [ "duplicate short name(s): -x" ];
  };

  testRejectBadName = {
    expr = errs { "bad-name" = { }; };
    expected = [ "invalid argument name(s) (need a bash identifier): bad-name" ];
  };

  testRejectShortTooLong = {
    expr = errs { foo.short = "ab"; };
    expected = [ "short must be a single letter: foo=\"ab\"" ];
  };

  testRejectBadType = {
    expr = errs { foo.type = "switch"; };
    expected = [ "invalid 'type' (allowed: option, flag, positional): foo=\"switch\"" ];
  };

  testRejectPositionalMissingIndex = {
    expr = errs { src.type = "positional"; };
    expected = [ "positional argument(s) missing 'index': src" ];
  };

  testRejectPositionalBadIndex = {
    expr = errs {
      src = {
        type = "positional";
        index = 0;
      };
    };
    expected = [ "positional 'index' must be an integer >= 1: src" ];
  };

  testRejectPositionalWithShort = {
    expr = errs {
      src = {
        type = "positional";
        index = 1;
        short = "s";
      };
    };
    expected = [ "positional argument(s) cannot take a 'short': src" ];
  };

  testRejectNonContiguousPositionals = {
    expr = errs {
      src = {
        type = "positional";
        index = 1;
      };
      dst = {
        type = "positional";
        index = 3;
      };
    };
    expected = [ "positional 'index' values must be contiguous starting at 1 (got: 1, 3)" ];
  };

  testRejectListDuplicateNames = {
    expr = errs [
      "foo"
      "foo"
    ];
    expected = [ "duplicate argument name(s): foo" ];
  };

  ### Error messages are part of the contract ###

  testDuplicateShortMessage = {
    expr = errs {
      a.short = "x";
      b.short = "x";
    };
    expected = [ "duplicate short name(s): -x" ];
  };
}
