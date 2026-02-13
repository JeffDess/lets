{ pkgs }:
let
  lint-nix-bash = pkgs.writeShellApplication {
    name = "lint-nix-bash";
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
  lint-nix = {
    description = "Lint Nix files with statix and deadnix";
    app = pkgs.writeShellApplication {
      name = "lint-nix";
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

  lint-bash = {
    description = "Lint bash fragments in Nix files and all .sh files";
    app = pkgs.writeShellApplication {
      name = "lint-bash";
      runtimeInputs = [
        pkgs.bash
        pkgs.fd
        pkgs.shfmt
        pkgs.shellcheck
      ];
      text = ''
        set -euo pipefail
        ${lint-nix-bash}/bin/lint-nix-bash

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
        ${lint-nix.app}/bin/lint-nix
        ${lint-bash.app}/bin/lint-bash
      '';
    };
  };
}
