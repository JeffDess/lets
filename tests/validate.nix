{ pkgs }:
let
  inherit (pkgs) lib;
  validate = import ../lib/validate.nix { inherit lib; };
  args = import ../lib/args.nix { inherit lib; };
  errs =
    rawArgs:
    validate {
      inherit rawArgs;
      normArgs = args.normalize rawArgs;
    };
  ok = rawArgs: errs rawArgs == [ ];
in
{
  ### Accepts valid shapes ###

  testValidEmpty = {
    expr = ok { };
    expected = true;
  };

  testValidOptionWithShort = {
    expr = ok { name.short = "n"; };
    expected = true;
  };

  testValidContiguousPositionals = {
    expr = ok {
      src = {
        type = "positional";
        index = 1;
      };
      dst = {
        type = "positional";
        index = 2;
      };
    };
    expected = true;
  };

  ### Rejects invalid shapes ###

  testRejectDuplicateShort = {
    expr = ok {
      a.short = "x";
      b.short = "x";
    };
    expected = false;
  };

  testRejectBadName = {
    expr = ok { "bad-name" = { }; };
    expected = false;
  };

  testRejectShortTooLong = {
    expr = ok { foo.short = "ab"; };
    expected = false;
  };

  testRejectBadType = {
    expr = ok { foo.type = "switch"; };
    expected = false;
  };

  testRejectPositionalMissingIndex = {
    expr = ok { src.type = "positional"; };
    expected = false;
  };

  testRejectPositionalBadIndex = {
    expr = ok {
      src = {
        type = "positional";
        index = 0;
      };
    };
    expected = false;
  };

  testRejectPositionalWithShort = {
    expr = ok {
      src = {
        type = "positional";
        index = 1;
        short = "s";
      };
    };
    expected = false;
  };

  testRejectNonContiguousPositionals = {
    expr = ok {
      src = {
        type = "positional";
        index = 1;
      };
      dst = {
        type = "positional";
        index = 3;
      };
    };
    expected = false;
  };

  testRejectListDuplicateNames = {
    expr = ok [
      "foo"
      "foo"
    ];
    expected = false;
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
