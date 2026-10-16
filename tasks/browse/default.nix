{ pkgs, mkTask, ... }:
{
  browse = mkTask {
    description = "Open URL in a browser (compatible with Linux/MacOS/WSL)";
    runtimeInputs =
      with pkgs;
      [
        coreutils
        gnugrep
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [ xdg-utils ];
    args = {
      url = {
        description = "URL to open in browser";
        type = "positional";
        index = 1;
        required = true;
      };
    };
    run = builtins.readFile ./browse.sh;
  };
}
