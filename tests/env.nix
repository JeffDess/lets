{ pkgs }:
let
  inherit (pkgs) lib;
  env = import ../lib/env.nix { inherit lib; };
in
{
  ### Auto-load line ###

  testAutoloadAlwaysEmitted = {
    expr = lib.hasSuffix "\n_lets_env_autoload" (env {
      envFiles = [ ];
      decoder = null;
    });
    expected = true;
  };

  testAutoloadEscapesNames = {
    expr = lib.hasInfix "\n_lets_env_autoload .env 'my file.env'" (env {
      envFiles = [
        ".env"
        "my file.env"
      ];
      decoder = null;
    });
    expected = true;
  };

  ### Decoder ###

  testNoDecoderIsEmpty = {
    expr = lib.hasInfix "_LETS_SECRET_BIN=''" (env {
      envFiles = [ ];
      decoder = null;
    });
    expected = true;
  };

  testDecoderIsBaked = {
    expr =
      let
        decoder = import ../lib/secrets.nix { inherit pkgs; } {
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
