{ pkgs, mkTask, ... }:
{
  release = mkTask {
    description = "Publish a GitHub release with git-cliff notes for the current tag";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      git
      git-cliff
      gh
      glow
    ];
    args = {
      dry_run = {
        description = "Print the release notes without creating the GitHub release";
        type = "flag";
      };
    };
    run = builtins.readFile ./release.sh;
  };
}
