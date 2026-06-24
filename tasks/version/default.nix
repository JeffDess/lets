{ pkgs, mkTask, ... }:
{
  version = mkTask {
    description = "Bump the flake version, refresh the changelog, commit and tag";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      git
      git-cliff
      semver-tool
      glow
    ];
    args = {
      level = {
        description = "Bump level: major, minor, patch, prerel, release (omit to auto-detect)";
        type = "positional";
        index = 1;
      };
      dry_run = {
        description = "Print the planned bump without writing, committing or tagging";
        type = "flag";
      };
    };
    run = builtins.readFile ./version.sh;
  };
}
