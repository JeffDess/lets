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
in
{
  ### Layers ###

  testModuleIncluded = {
    expr = lib.hasInfix "dotenv_eval_string() {" plain;
    expected = true;
  };

  testLayersInOrder = {
    expr = lib.hasSuffix (lib.concatStringsSep "\n" [
      "{"
      "  _lets_env_no_files_check"
      "  _lets_env_vars"
      "  _lets_env_files .env 'my file.env'"
      "  _lets_env_secret_files"
      "  _lets_env_files t.env"
      "  _lets_env_task_secrets dev"
      "  _lets_env_cli"
      "  _lets_env_export"
      "}"
    ]) plain;
    expected = true;
  };

  testEmptyLayersHaveNoArguments = {
    expr = lib.hasInfix "  _lets_env_files\n  _lets_env_secret_files\n" (env {
      envFiles = [ ];
      decoder = null;
    });
    expected = true;
  };

  testReservedPatterns = {
    expr =
      lib.hasInfix "_LETS_ENV_RESERVED=('_lets_*' '_LETS_*' '_dotenv_*' DOTENV_ERROR DOTENV_ERROR_KIND DOTENV_SKIPPED 'BASH_*' PATH " plain
      && lib.hasInfix " name)\n" plain;
    expected = true;
  };

  ### Decoder ###

  testNoDecoderIsEmpty = {
    expr = lib.hasInfix "_LETS_SECRET_BIN=''" plain;
    expected = true;
  };

  testDecoderIsBaked = {
    expr =
      let
        decoder = import ../../lib/secrets.nix { inherit pkgs; } {
          command = "sops -d {}";
          pattern = ".{name}.enc.env";
          files = [ "base" ];
          onError = "warn";
        };
        text = builtins.unsafeDiscardStringContext (env {
          envFiles = [ ];
          inherit decoder;
        });
      in
      lib.hasInfix (builtins.unsafeDiscardStringContext "_LETS_SECRET_BIN=${decoder.package}/bin/lets-decoder") text
      && lib.hasInfix (builtins.unsafeDiscardStringContext "_LETS_SECRET_DRV=${decoder.package.drvPath}") text
      && lib.hasInfix "_LETS_SECRET_PATTERN='.{name}.enc.env'" text
      && lib.hasInfix "_LETS_SECRET_ON_ERROR=warn" text
      && lib.hasInfix "_LETS_SECRET_FILES=(base)" text;
    expected = true;
  };
}
