{ pkgs }:
let
  mkTask = import ../lib/mkTask.nix { inherit pkgs; };
  build = cfg: (mkTask cfg).__build "test";
  builds = cfg: (builtins.tryEval (build cfg)).success;

  base = {
    description = "demo";
    run = "true";
  };
in
{
  ### Passthrough ###

  testDescriptionPassthrough = {
    expr = (build base).description;
    expected = "demo";
  };

  ### Normalisation ###

  testListArgsNormalised = {
    expr =
      builtins.attrNames
        (build (
          base
          // {
            args = [
              "foo"
              "bar"
            ];
          }
        )).args;
    expected = [
      "bar"
      "foo"
    ];
  };

  ### Valid configs ###

  testMinimalValid = {
    expr = builds base;
    expected = true;
  };

  testOptionArgValid = {
    expr = builds (
      base
      // {
        args.name = {
          short = "n";
          default = "World";
        };
      }
    );
    expected = true;
  };

  testFlagArgValid = {
    expr = builds (base // { args.verbose.type = "flag"; });
    expected = true;
  };

  testPositionalsValid = {
    expr = builds (
      base
      // {
        args = {
          src = {
            type = "positional";
            index = 1;
          };
          dst = {
            type = "positional";
            index = 2;
          };
        };
      }
    );
    expected = true;
  };

  testListArgsValid = {
    expr = builds (
      base
      // {
        args = [
          "foo"
          "bar"
        ];
      }
    );
    expected = true;
  };

  ### Invalid configs ###

  testRejectDuplicateShort = {
    expr = builds (
      base
      // {
        args = {
          a.short = "x";
          b.short = "x";
        };
      }
    );
    expected = false;
  };

  testRejectBadName = {
    expr = builds (base // { args."bad-name" = { }; });
    expected = false;
  };

  testRejectShortTooLong = {
    expr = builds (base // { args.foo.short = "ab"; });
    expected = false;
  };

  testRejectBadType = {
    expr = builds (base // { args.foo.type = "switch"; });
    expected = false;
  };

  testRejectPositionalMissingIndex = {
    expr = builds (base // { args.src.type = "positional"; });
    expected = false;
  };

  testRejectPositionalBadIndex = {
    expr = builds (
      base
      // {
        args.src = {
          type = "positional";
          index = 0;
        };
      }
    );
    expected = false;
  };

  testRejectPositionalWithShort = {
    expr = builds (
      base
      // {
        args.src = {
          type = "positional";
          index = 1;
          short = "s";
        };
      }
    );
    expected = false;
  };

  testRejectPositionalsNonContiguous = {
    expr = builds (
      base
      // {
        args = {
          src = {
            type = "positional";
            index = 1;
          };
          dst = {
            type = "positional";
            index = 3;
          };
        };
      }
    );
    expected = false;
  };

  testRejectListDuplicateNames = {
    expr = builds (
      base
      // {
        args = [
          "foo"
          "foo"
        ];
      }
    );
    expected = false;
  };
}
