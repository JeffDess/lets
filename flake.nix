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
      version = "0.0.1";
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
      runTask = mkLets { inherit pkgs tasks version; };
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
          mkTasksFromDir
          mkBaseTasks
          ;
        mkLets = args: mkLets (args // { inherit version; });
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
        release-flow = pkgs.runCommand "check-release-flow" { nativeBuildInputs = [ pkgs.git ]; } ''
          export HOME="$TMPDIR"
          git config --global user.email ci@lets.test
          git config --global user.name ci
          git config --global init.defaultBranch main

          mkdir repo && cd repo
          git init -q
          cp ${./cliff.toml} cliff.toml
          printf '{\n  version = "1.2.3";\n}\n' >flake.nix
          git add .
          git commit -q -m "feat: a feature"
          git tag -a v1.2.3 -m v1.2.3
          git commit -q --allow-empty -m "feat: unreleased work"

          head_before="$(git rev-parse HEAD)"
          forced="$(${taskOutputs.packages.version}/bin/version minor --dry-run)"
          case $forced in
          *"1.2.3 -> 1.3.0"*) echo "✅ version minor --dry-run computes the bump" ;;
          *)
            echo "❌ version minor --dry-run output: $forced" >&2
            exit 1
            ;;
          esac
          auto="$(${taskOutputs.packages.version}/bin/version --dry-run)"
          case $auto in
          *"1.2.3 -> 1.3.0"*) echo "✅ version --dry-run auto-detects the bump" ;;
          *)
            echo "❌ version --dry-run (auto) output: $auto" >&2
            exit 1
            ;;
          esac
          if [ "$(git rev-parse HEAD)" != "$head_before" ]; then
            echo "❌ version --dry-run mutated the repository" >&2
            exit 1
          fi

          git checkout -q v1.2.3
          notes="$(GITHUB_REF_NAME=v1.2.3 ${taskOutputs.packages.release}/bin/release --dry-run)"
          case $notes in
          *"### Features"*) echo "✅ release --dry-run renders notes" ;;
          *)
            echo "❌ release --dry-run output: $notes" >&2
            exit 1
            ;;
          esac
          case $notes in
          *"## ["*)
            echo "❌ release notes still contain a version heading" >&2
            exit 1
            ;;
          *) echo "✅ release notes omit the redundant version heading" ;;
          esac

          if GITHUB_REF_NAME=v9.9.9 ${taskOutputs.packages.release}/bin/release --dry-run 2>/dev/null; then
            echo "❌ release accepted a tag/version mismatch" >&2
            exit 1
          fi
          echo "✅ release rejects tag/version mismatch"

          touch "$out"
        '';
        unit =
          pkgs.runCommand "check-unit"
            {
              failuresJson = builtins.toJSON (pkgs.lib.runTests (import ./tests/mkTask.nix { inherit pkgs; }));
            }
            ''
              if [ "$failuresJson" = "[]" ]; then
                echo "✅ unit tests passed"
                touch "$out"
              else
                echo "❌ unit test failures:" >&2
                printf '%s\n' "$failuresJson" >&2
                exit 1
              fi
            '';
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            convco.enable = true;
            deadnix = {
              enable = true;
              settings.edit = true;
            };
            editorconfig-checker.enable = true;
            nixfmt.enable = true;
            shellcheck.enable = true;
            shfmt = {
              enable = true;
              settings.indent = 2;
            };
            statix.enable = true;
            typos.enable = true;
          };
        };
      };
    };
}
