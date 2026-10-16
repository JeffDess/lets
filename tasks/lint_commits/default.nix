{ pkgs, mkTask, ... }:
{
  lint_commits = mkTask {
    description = "Lint commit messages with convco";
    runtimeInputs = with pkgs; [
      convco
      git
      gnused
    ];
    args = {
      from = {
        description = "Excluded base commit ($PRE_COMMIT_FROM_REF, else the latest v* tag)";
        default = [ "$PRE_COMMIT_FROM_REF" ];
      };
      to = {
        description = "Last commit to lint";
        default = [
          "$PRE_COMMIT_TO_REF"
          "HEAD"
        ];
      };
      message_file = {
        description = "Lint this commit message file instead of a range";
      };
      allow_fixup = {
        description = "Let fixup!, squash! and amend! commits through";
        type = "flag";
      };
      protect = {
        description = "Reject fixups only when pushing to this branch";
      };
    };
    run = builtins.readFile ./lint-commits.sh;
  };
}
