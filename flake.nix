{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
      mkTask = import ./lib/mkTask.nix;
      mkTasks = import ./lib/mkTasks.nix;
      mkTasksFromDir = import ./lib/mkTasksFromDir.nix;
      mkOutputs = import ./lib/mkOutputs.nix;
      mkLets = import ./lib/mkLets.nix;
      mkBaseTasks = import ./lib/mkBaseTasks.nix;
      tasks = mkBaseTasks { inherit pkgs; };
      taskOutputs = mkOutputs { inherit pkgs tasks; };
      runTask = mkLets { inherit pkgs tasks; };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [ runTask ];
          inherit shellHook;
          buildInputs = enabledPackages;
        };
      };

      apps.${system} = taskOutputs.apps;

      packages.${system} = {
        default = runTask;
        lets = runTask;
      };

      lib.${system} = {
        inherit
          mkTask
          mkTasks
          mkOutputs
          mkLets
          mkTasksFromDir
          mkBaseTasks
          ;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        demo = pkgs.runCommand "check-demo" { } ''
          # shellcheck disable=SC2154
          ${taskOutputs.packages.demo}/bin/demo
          touch "$out"
        '';
        colors = pkgs.runCommand "check-colors" { } ''
          # shellcheck disable=SC2154
          bin=${taskOutputs.packages.colors}/bin/colors
          esc=$'\033['
          # Capture to a variable (no pipe) so the task is never killed by SIGPIPE.
          # runCommand has no tty, so color is off unless FORCE_COLOR is set.
          forced="$(FORCE_COLOR=1 "$bin")"

          case $forced in
          *"$esc"*) echo "✅ ANSI codes emitted when forced" ;;
          *)
            echo "❌ expected ANSI codes with FORCE_COLOR=1" >&2
            exit 1
            ;;
          esac

          plain="$("$bin")"

          case $plain in
          *"$esc"*)
            echo "❌ ANSI codes leaked when not a tty" >&2
            exit 1
            ;;
          *) echo "✅ plain text when not a tty" ;;
          esac

          touch "$out"
        '';
        lint = pkgs.runCommand "check-lint" { src = self; } ''
          cp -r "$src" source
          chmod -R +w source
          cd source || exit
          ${taskOutputs.packages.lint}/bin/lint
          touch "$out"
        '';
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            editorconfig-checker.enable = true;
            convco.enable = true;
            shellcheck.enable = true;
            shfmt = {
              enable = true;
              settings = {
                indent = 2;
              };
            };
            typos.enable = true;
          };
        };
      };
    };
}
