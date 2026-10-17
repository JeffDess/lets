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
    });
    expected = true;
  };

  testAutoloadEscapesNames = {
    expr = lib.hasInfix "\n_lets_env_autoload .env 'my file.env'" (env {
      envFiles = [
        ".env"
        "my file.env"
      ];
    });
    expected = true;
  };
}
