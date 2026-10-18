{ pkgs }:
let
  loadTasks = import ../lib/loadTasks.nix;
  inherit (pkgs) lib;
  envFilesErrors = import ../lib/envFiles.nix { inherit lib; };
  secretsErrors = import ../lib/secretsErrors.nix { inherit lib; };
  withCommand = extra: secretsErrors ({ command = "sops -d {}"; } // extra);
  pathsMsg = ''lets: envFiles must be strings (".env"), not paths: they are read at runtime, not copied to the store'';
  loadsWith =
    extra: src:
    (builtins.tryEval (builtins.attrNames (loadTasks ({ inherit pkgs src; } // extra)))).success;
  loads = loadsWith { };
  inlineTask =
    name:
    (
      { mkTask, ... }:
      {
        ${name} = mkTask {
          description = "x";
          run = "true";
        };
      }
    );
in
{
  ### Reserved task names (clash with lets builtins) ###

  testReservedHelpRejected = {
    expr = loads (inlineTask "help");
    expected = false;
  };

  testReservedLetsRejected = {
    expr = loads (inlineTask "lets");
    expected = false;
  };

  testNonReservedAccepted = {
    expr = loads (inlineTask "greet");
    expected = true;
  };

  ### Duplicate task names across files ###

  testDuplicateAcrossFilesRejected = {
    expr = loads ./fixtures/dup-tasks;
    expected = false;
  };

  ### envFiles ###

  testEnvFilesPathRejected = {
    expr = loadsWith { envFiles = [ ../README.md ]; } (inlineTask "greet");
    expected = false;
  };

  testEnvFilesPathMessage = {
    expr = envFilesErrors [ ../README.md ];
    expected = [ pathsMsg ];
  };

  testEnvFilesStorePathStringMessage = {
    expr = envFilesErrors [ "${../README.md}" ];
    expected = [ pathsMsg ];
  };

  testEnvFilesNotListMessage = {
    expr = envFilesErrors ".env";
    expected = [ ''lets: envFiles must be a list, e.g. [ ".env" ]'' ];
  };

  testEnvFilesNonStringMessage = {
    expr = envFilesErrors [ 1 ];
    expected = [ "lets: envFiles must be a list of strings" ];
  };

  testEnvFilesEmptyMessage = {
    expr = envFilesErrors [ "" ];
    expected = [ "lets: envFiles entries cannot be empty" ];
  };

  testEnvFilesUnsupportedExpansionMessage = {
    expr = envFilesErrors [
      "$(: >pwned).env"
      "\${DIR:-.}/.env"
      "price$.env"
    ];
    expected = [
      "lets: envFiles entry '$(: >pwned).env' can only expand $VAR and \${VAR}"
      "lets: envFiles entry '\${DIR:-.}/.env' can only expand $VAR and \${VAR}"
      "lets: envFiles entry 'price$.env' can only expand $VAR and \${VAR}"
    ];
  };

  testEnvFilesValid = {
    expr = envFilesErrors [
      ".env"
      "~/x.env"
      "$HOME/a.env"
      "\${XDG_CONFIG_HOME}/lets/$PROFILE.env"
    ];
    expected = [ ];
  };

  testEnvFilesReachTasks = {
    expr =
      let
        ts = loadTasks {
          inherit pkgs;
          src = inlineTask "greet";
          envFiles = [ ".env" ];
        };
      in
      lib.hasInfix "  _lets_env_files .env\n" ts.greet.app.text;
    expected = true;
  };

  testBaseTasksForwardEnvFiles = {
    expr =
      let
        bt = import ../lib/mkBaseTasks.nix {
          inherit pkgs;
          envFiles = [ ".env" ];
        };
      in
      lib.hasInfix "  _lets_env_files .env\n" bt.browse.app.text;
    expected = true;
  };

  testBaseTasksForwardSecrets = {
    expr =
      let
        bt = import ../lib/mkBaseTasks.nix {
          inherit pkgs;
          secrets = {
            command = "dec {}";
            files = [ "base" ];
          };
        };
      in
      lib.hasInfix "_LETS_SECRET_FILES=(base)\n" bt.browse.app.text;
    expected = true;
  };

  ### secrets ###

  testSecretsCommandNeedsBraces = {
    expr = loadsWith {
      secrets.command = "sops -d";
    } (inlineTask "greet");
    expected = false;
  };

  testSecretsCommandAccepted = {
    expr = loadsWith {
      secrets.command = "sops -d {}";
    } (inlineTask "greet");
    expected = true;
  };

  testSecretsOnErrorValidated = {
    expr = loadsWith {
      secrets = {
        command = "sops -d {}";
        onError = "retry";
      };
    } (inlineTask "greet");
    expected = false;
  };

  testSecretsPatternNeedsName = {
    expr = loadsWith {
      secrets = {
        command = "sops -d {}";
        pattern = ".enc.env";
      };
    } (inlineTask "greet");
    expected = false;
  };

  testSecretsFilesMustBeStrings = {
    expr = loadsWith {
      secrets = {
        command = "sops -d {}";
        files = "base";
      };
    } (inlineTask "greet");
    expected = false;
  };

  testSecretsUnknownKeyRejected = {
    expr = loadsWith {
      secrets = {
        command = "sops -d {}";
        extra = "{name}";
      };
    } (inlineTask "greet");
    expected = false;
  };

  testSecretsNotAttrsMessage = {
    expr = secretsErrors "sops -d {}";
    expected = [ ''lets: secrets must be an attribute set, e.g. { command = "sops -d {}"; }'' ];
  };

  testSecretsCommandMissingMessage = {
    expr = secretsErrors { pattern = "{name}"; };
    expected = [ "lets: secrets.command is required" ];
  };

  testSecretsCommandTypeMessage = {
    expr = secretsErrors { command = 42; };
    expected = [ "lets: secrets.command must be a string or a list of words" ];
  };

  testSecretsCommandSlotMessage = {
    expr = secretsErrors { command = "sops --file={}"; };
    expected = [ "lets: secrets.command must contain {} as a word of its own" ];
  };

  testSecretsCommandSplitsOnWhitespace = {
    expr = map (c: secretsErrors { command = c; }) [
      "sops\t-d {}"
      "\n  sops -d\n  {}\n"
    ];
    expected = [
      [ ]
      [ ]
    ];
  };

  testSecretsCommandWordsReachTheDecoder = {
    expr =
      lib.hasInfix ''exec sops -d "$1"''
        (import ../lib/secrets.nix { inherit pkgs; } { command = "\tsops\t-d  {}\n"; }).package.text;
    expected = true;
  };

  testSecretsCommandStringKeepsStorePaths = {
    expr =
      let
        tool = pkgs.writeText "tool" "";
        inherit ((import ../lib/secrets.nix { inherit pkgs; } { command = "${tool} {}"; }).package) text;
      in
      builtins.hasAttr (builtins.unsafeDiscardStringContext tool.drvPath) (builtins.getContext text);
    expected = true;
  };

  testSecretsCommandShellCharsMessage = {
    expr = lib.unique (
      map (c: secretsErrors { command = c; }) [
        "sh -c 'sops -d {}'"
        ''sops -d "{}"''
        "sops -d {} | jq"
        "sops -d {}; true"
        "sops -d {} && true"
        "sops -d {} >out"
        "sops -d {} <in"
        "sops -d $HOME/{}"
        "sops -d {} `x`"
        "sops\\ -d {}"
      ]
    );
    expected = [
      [
        "lets: secrets.command is split on spaces, not run by a shell: write it as a list"
      ]
    ];
  };

  testSecretsCommandListKeepsShellChars = {
    expr = secretsErrors {
      command = [
        "sh"
        "-c"
        ''sops -d "$1" | jq''
        "_"
        "{}"
      ];
    };
    expected = [ ];
  };

  testSecretsCommandListAccepted = {
    expr = secretsErrors {
      command = [
        "dec"
        "a b"
        "{}"
      ];
    };
    expected = [ ];
  };

  testSecretsUnknownMessage = {
    expr = withCommand { extra = 1; };
    expected = [ "lets: unknown secrets attribute(s): extra" ];
  };

  testSecretsInputsMessage = {
    expr = withCommand { runtimeInputs = "sops"; };
    expected = [ "lets: secrets.runtimeInputs must be a list or a function of pkgs" ];
  };

  testSecretsPatternOnceMessage = {
    expr = withCommand { pattern = "{name}/{name}.env"; };
    expected = [ "lets: secrets.pattern must be a string containing {name} once" ];
  };

  testSecretsFilesMessage = {
    expr = withCommand { files = [ "" ]; };
    expected = [ "lets: secrets.files must be a list of non-empty strings" ];
  };

  testSecretsOnErrorMessage = {
    expr = withCommand { onError = "retry"; };
    expected = [ ''lets: secrets.onError must be "fail", "warn" or "ignore"'' ];
  };

  testSecretsReachTasks = {
    expr =
      let
        ts = loadTasks {
          inherit pkgs;
          src = inlineTask "greet";
          secrets.command = "fakedec --flag {}";
        };
      in
      lib.hasInfix "/bin/lets-decoder" ts.greet.app.text;
    expected = true;
  };
}
