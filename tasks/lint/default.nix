{ pkgs, ... }:
let
  lint_nix-bash = pkgs.writeShellApplication {
    name = "lint_nix-bash";
    runtimeInputs = [
      pkgs.findutils
      pkgs.gawk
      pkgs.shfmt
      pkgs.shellcheck
    ];
    text = builtins.readFile ./lint-nix-bash-fragments.sh;
  };
in
rec {
  lint_nix = {
    description = "Lint Nix files with statix and deadnix";
    app = pkgs.writeShellApplication {
      name = "lint_nix";
      runtimeInputs = [
        pkgs.statix
        pkgs.deadnix
      ];
      text = ''
        set -euo pipefail
        statix check .
        deadnix .
        echo "✅ Nix linter passed"
      '';
    };
  };

  lint_bash = {
    description = "Lint bash fragments in Nix files and all .sh files";
    app = pkgs.writeShellApplication {
      name = "lint_bash";
      runtimeInputs = [
        pkgs.bash
        pkgs.fd
        pkgs.shfmt
        pkgs.shellcheck
      ];
      text = ''
        set -euo pipefail
        ${lint_nix-bash}/bin/lint_nix-bash

        fd --hidden --exclude .git --type f --extension sh --print0 |
          xargs -0 -r sh -c 'shfmt -d -i 2 "$@"; shellcheck "$@"' _

        echo "✅ Bash linter passed"
      '';
    };
  };

  lint = {
    description = "Run all lint tasks";
    app = pkgs.writeShellApplication {
      name = "lint";
      text = ''
        ${lint_nix.app}/bin/lint_nix
        ${lint_bash.app}/bin/lint_bash
      '';
    };
  };
}
