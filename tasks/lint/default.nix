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

  lint = mkTask {
    description = "Run all lint tasks";
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
