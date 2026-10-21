{ pkgs }:
let
  inherit (pkgs) lib;
  env = import ../../lib/env.nix { inherit lib; };
  plain = env {
    envFiles = [
      ".env"
      "my file.env"
    ];
    taskEnvFiles = [ "t.env" ];
    secrets = [ "dev" ];
    argNames = [ "name" ];
    decoder = null;
  };
  layers = text: lib.splitString "\n" (lib.last (lib.splitString "\n{\n" text));
  secretVars = text: builtins.filter (lib.hasPrefix "_LETS_SECRET_") (lib.splitString "\n" text);
in
{
  ### Layers ###

  testModuleIncluded = {
    expr = lib.hasInfix "dotenv_eval_string() {" plain;
    expected = true;
  };

  testLayersInOrder = {
    expr = layers plain;
    expected = [
      "  _lets_env_no_files_check"
      "  _lets_env_vars"
      "  _lets_env_files .env 'my file.env'"
      "  _lets_env_secret_files"
      "  _lets_env_files t.env"
      "  _lets_env_task_secrets dev"
      "  _lets_env_cli"
      "  _lets_env_export"
      "}"
    ];
  };

  testEmptyLayersHaveNoArguments = {
    expr = layers (env {
      envFiles = [ ];
      decoder = null;
    });
    expected = [
      "  _lets_env_no_files_check"
      "  _lets_env_vars"
      "  _lets_env_files"
      "  _lets_env_secret_files"
      "  _lets_env_files"
      "  _lets_env_task_secrets"
      "  _lets_env_cli"
      "  _lets_env_export"
      "}"
    ];
  };

  testReservedPatterns = {
    expr =
      lib.hasInfix "_LETS_ENV_RESERVED=('_lets_*' '_LETS_*' '_dotenv_*' DOTENV_ERROR DOTENV_ERROR_KIND DOTENV_SKIPPED 'BASH_*' PATH " plain
      && lib.hasInfix " name)\n" plain;
    expected = true;
  };

  ### Decoder ###

  testNoDecoderIsEmpty = {
    expr = secretVars plain;
    expected = [
      "_LETS_SECRET_BIN=''"
      "_LETS_SECRET_DRV=''"
      "_LETS_SECRET_PATTERN='{name}'"
      "_LETS_SECRET_ON_ERROR=fail"
      "_LETS_SECRET_FILES=()"
    ];
  };

  testDecoderIsBaked =
    let
      decoder = import ../../lib/secrets.nix { inherit pkgs; } {
        command = "sops -d {}";
        pattern = ".{name}.enc.env";
        files = [ "base" ];
        onError = "warn";
      };
    in
    {
      expr = map builtins.unsafeDiscardStringContext (
        secretVars (env {
          envFiles = [ ];
          inherit decoder;
        })
      );
      expected = map builtins.unsafeDiscardStringContext [
        "_LETS_SECRET_BIN=${decoder.package}/bin/lets-decoder"
        "_LETS_SECRET_DRV=${decoder.package.drvPath}"
        "_LETS_SECRET_PATTERN='.{name}.enc.env'"
        "_LETS_SECRET_ON_ERROR=warn"
        "_LETS_SECRET_FILES=(base)"
      ];
    };
}
