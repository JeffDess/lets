{ pkgs }:
let
  loadTasks = import ../lib/loadTasks.nix;
  inherit (pkgs) lib;
  envFilesErrors = import ../lib/envFiles.nix { inherit lib; };
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
      lib.hasInfix "_lets_env_autoload .env" ts.greet.app.text;
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
      lib.hasInfix "_lets_env_autoload .env" bt.browse.app.text;
    expected = true;
  };
}
