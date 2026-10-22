{
  pkgs,
  mkTask,
  tasks,
  ...
}:
{
  lint_nix-bash = mkTask {
    description = "Lint bash fragments embedded in Nix files";
    runtimeInputs = with pkgs; [
      findutils
      gawk
      shfmt
      shellcheck
    ];
    run = builtins.readFile ./lint-nix-bash-fragments.sh;
  };

  lint_nix = mkTask {
    description = "Lint Nix files with statix and deadnix";
    runtimeInputs = with pkgs; [
      statix
      deadnix
    ];
    run = ''
      statix check .
      deadnix --fail .
      echo "✅ Nix linter passed"
    '';
  };

  lint_bash = mkTask {
    description = "Lint bash fragments in Nix files and all .sh files";
    runtimeInputs = with pkgs; [
      bash
      fd
      shfmt
      shellcheck
      tasks.lint_nix-bash.app
    ];
    run = ''
      lint_nix-bash

      fd --hidden --exclude .git --type f --extension sh --print0 |
        xargs -0 -r sh -c 'shfmt -d -i 2 "$@" && shellcheck "$@"' _

      echo "✅ Bash linter passed"
    '';
  };

  lint_editor = mkTask {
    description = "Lint with editorconfig-checker";
    runtimeInputs = with pkgs; [ editorconfig-checker ];
    run = ''
      set -euo pipefail
      editorconfig-checker
      echo "✅ Editorconfig linter passed"
    '';
  };

  lint_commits = mkTask {
    description = "Lint commit messages with convco";
    runtimeInputs = with pkgs; [
      convco
      gitMinimal
      gnused
    ];
    args = {
      from = {
        description = "Excluded base commit ($PRE_COMMIT_FROM_REF, else the latest v* tag)";
        short = "f";
        default = [ "$PRE_COMMIT_FROM_REF" ];
      };
      to = {
        description = "Last commit to lint";
        short = "t";
        default = [
          "$PRE_COMMIT_TO_REF"
          "HEAD"
        ];
      };
      message_file = {
        description = "Lint this commit message file instead of a range";
        short = "m";
      };
      allow_fixup = {
        description = "Let fixup!, squash! and amend! commits through";
        type = "flag";
        short = "a";
      };
      protect = {
        description = "Reject fixups only when pushing to this branch";
        short = "p";
      };
    };
    run = builtins.readFile ./lint-commits.sh;
  };

  lint = mkTask {
    description = "Run all lint tasks";
    keepGoing = true;
    runtimeInputs = with tasks; [
      lint_nix.app
      lint_bash.app
      lint_editor.app
    ];
    run = ''
      lint_nix
      lint_bash
      lint_editor
    '';
  };
}
