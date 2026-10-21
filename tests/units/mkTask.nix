{ pkgs }:
let
  inherit (pkgs) lib;
  mkTask = import ../../lib/mkTask.nix { inherit pkgs; };
  build = cfg: (mkTask cfg).__build "test";
  builds = cfg: (builtins.tryEval (build cfg)).success;

  secretsFixture = {
    command = "fakedec {}";
    runtimeInputs = _: [ pkgs.hello ];
  };
  decoderFixture = import ../../lib/secrets.nix { inherit pkgs; } secretsFixture;
  decoderContext =
    built:
    (builtins.getContext built.app.text)
    .${builtins.unsafeDiscardStringContext decoderFixture.package.drvPath} or { };

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
    expr = build (
      base
      // {
        args = {
          a.short = "x";
          b.short = "x";
        };
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "duplicate short name.*: -x";
    };
  };

  testRejectBadName = {
    expr = build (base // { args."bad-name" = { }; });
    expectedError = {
      type = "ThrownError";
      msg = "invalid argument name.*: bad-name";
    };
  };

  testRejectReservedArgName = {
    expr = build (base // { args.help = { }; });
    expectedError = {
      type = "ThrownError";
      msg = "argument name.* reserved .*: help";
    };
  };

  testRejectShortTooLong = {
    expr = build (base // { args.foo.short = "ab"; });
    expectedError = {
      type = "ThrownError";
      msg = "short must be a single letter: foo=\"ab\"";
    };
  };

  testRejectBadType = {
    expr = build (base // { args.foo.type = "switch"; });
    expectedError = {
      type = "ThrownError";
      msg = "invalid 'type'.*: foo=\"switch\"";
    };
  };

  testRejectPositionalMissingIndex = {
    expr = build (base // { args.src.type = "positional"; });
    expectedError = {
      type = "ThrownError";
      msg = "missing 'index': src";
    };
  };

  testRejectPositionalBadIndex = {
    expr = build (
      base
      // {
        args.src = {
          type = "positional";
          index = 0;
        };
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "positional 'index' must be an integer >= 1: src";
    };
  };

  testRejectPositionalWithShort = {
    expr = build (
      base
      // {
        args.src = {
          type = "positional";
          index = 1;
          short = "s";
        };
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "cannot take a 'short': src";
    };
  };

  testRejectPositionalsNonContiguous = {
    expr = build (
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
    expectedError = {
      type = "ThrownError";
      msg = "must be contiguous starting at 1 \\(got: 1, 3\\)";
    };
  };

  # Mirrors the README "Value aliases" example: a built base task's
  # attributes must be reusable as mkTask input.
  testBaseTaskOverrideWithAliases = {
    expr =
      let
        base' = (import ../../lib/mkBaseTasks.nix { inherit pkgs; }).browse;
        task = build {
          inherit (base') description runtimeInputs run;
          args = base'.args // {
            url = base'.args.url // {
              required = false;
              default = "https://example.com";
              aliases.docs = "https://example.com/docs";
            };
          };
        };
      in
      (builtins.tryEval task.app.drvPath).success
      && task.args.url.aliases.docs == "https://example.com/docs";
    expected = true;
  };

  testLintCommitsBaseTaskBuilds = {
    expr =
      let
        task = (import ../../lib/mkBaseTasks.nix { inherit pkgs; }).lint_commits;
      in
      (builtins.tryEval task.app.drvPath).success
      &&
        builtins.attrNames task.args == [
          "allow_fixup"
          "from"
          "message_file"
          "protect"
          "to"
        ];
    expected = true;
  };

  testRejectListDuplicateNames = {
    expr = build (
      base
      // {
        args = [
          "foo"
          "foo"
        ];
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "duplicate argument name.*: foo";
    };
  };

  ### Env preamble ###

  testEnvFilesCheckedByMkTask = {
    expr =
      let
        mkTaskEnv = import ../../lib/mkTask.nix {
          inherit pkgs;
          envFiles = [ "$1/.env" ];
        };
      in
      (mkTaskEnv base).__build "test";
    expectedError = {
      type = "ThrownError";
      msg = "envFiles entry '\\$1/\\.env' can only expand";
    };
  };

  testEnvPreambleAlwaysIncluded = {
    expr = lib.hasInfix "_lets_env_export" (build (base // { run = "true"; })).app.text;
    expected = true;
  };

  testTaskEnvFilesReachPreamble = {
    expr =
      lib.hasInfix "  _lets_env_files .deploy.env\n"
        (build (base // { envFiles = [ ".deploy.env" ]; })).app.text;
    expected = true;
  };

  testTaskEnvFilesChecked = {
    expr = build (base // { envFiles = [ ../../README.md ]; });
    expectedError = {
      type = "ThrownError";
      msg = "envFiles must be strings";
    };
  };

  testTaskSecretsReachPreamble = {
    expr =
      let
        mkTaskSec = import ../../lib/mkTask.nix {
          inherit pkgs;
          secrets = secretsFixture;
        };
      in
      lib.hasInfix "  _lets_env_task_secrets dev\n"
        ((mkTaskSec (base // { secrets = [ "dev" ]; })).__build "test").app.text;
    expected = true;
  };

  ### Task secrets ###

  testTaskSecretsMustBeList = {
    expr = build (base // { secrets = "dev"; });
    expectedError = {
      type = "ThrownError";
      msg = "secrets must be a list of non-empty strings";
    };
  };

  testTaskSecretsNamesNotEmpty = {
    expr = build (base // { secrets = [ "" ]; });
    expectedError = {
      type = "ThrownError";
      msg = "secrets must be a list of non-empty strings";
    };
  };

  testTaskSecretsNeedDecoder = {
    expr = build (base // { secrets = [ "dev" ]; });
    expectedError = {
      type = "ThrownError";
      msg = "secrets needs a project-wide secrets\\.command";
    };
  };

  testDecoderOutOfClosureWhenUnused = {
    expr =
      let
        mkTaskSec = import ../../lib/mkTask.nix {
          inherit pkgs;
          secrets = secretsFixture;
        };
        built = (mkTaskSec base).__build "test";
      in
      !builtins.elem decoderFixture.package built.runtimeInputs
      && decoderContext built == { }
      && lib.hasInfix (builtins.unsafeDiscardStringContext "${decoderFixture.package}/bin/lets-decoder") (
        builtins.unsafeDiscardStringContext built.app.text
      );
    expected = true;
  };

  testDecoderInClosureWhenTaskDecrypts = {
    expr =
      let
        mkTaskSec = import ../../lib/mkTask.nix {
          inherit pkgs;
          secrets = secretsFixture;
        };
        built = (mkTaskSec (base // { secrets = [ "dev" ]; })).__build "test";
      in
      decoderContext built ? outputs && !(decoderContext built ? path);
    expected = true;
  };

  testTaskKeepsItsOwnInputsAndSecrets = {
    expr =
      let
        mkTaskSec = import ../../lib/mkTask.nix {
          inherit pkgs;
          secrets = secretsFixture;
        };
        built =
          (mkTaskSec (
            base
            // {
              secrets = [ "dev" ];
              runtimeInputs = [ pkgs.jq ];
            }
          )).__build
            "test";
      in
      {
        inherit (built) secrets;
        inputs = map lib.getName built.runtimeInputs;
      };
    expected = {
      secrets = [ "dev" ];
      inputs = [ "jq" ];
    };
  };

  testDecoderInClosureWithProjectFiles = {
    expr =
      let
        mkTaskSec = import ../../lib/mkTask.nix {
          inherit pkgs;
          secrets = secretsFixture // {
            files = [ "base" ];
          };
        };
        built = (mkTaskSec base).__build "test";
      in
      decoderContext built ? outputs && !(decoderContext built ? path);
    expected = true;
  };
}
