{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
      flake-parts,
    }:
    let
      system = "x86_64-linux";
      version = "0.0.1";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
      mkTask = import ./lib/mkTask.nix;
      mkTasks = import ./lib/mkTasks.nix;
      loadTasks = import ./lib/loadTasks.nix;
      mkOutputs = import ./lib/mkOutputs.nix;
      mkLets = import ./lib/mkLets.nix;
      mkBaseTasks = import ./lib/mkBaseTasks.nix;
      mkFlake = import ./lib/mkFlake.nix;
      tasks = mkBaseTasks { inherit pkgs; };
      taskOutputs = mkOutputs { inherit pkgs tasks; };
      letsCmd = mkLets { inherit pkgs tasks version; };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [ letsCmd ];
          shellHook = ''
            ${shellHook}
            __lets_bash_version="''${BASH_VERSION:-}"
            if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
              # shellcheck disable=SC1091
              source ${taskOutputs.completionScripts.bash}
            fi
          '';
          buildInputs = enabledPackages;
        };
      };

      apps.${system} = taskOutputs.apps;

      packages.${system} = {
        default = letsCmd;
        lets = letsCmd;
        completions =
          pkgs.runCommand "lets-completions"
            {
              nativeBuildInputs = [ pkgs.installShellFiles ];
            }
            ''
              # shellcheck disable=SC2154
              installShellCompletion --cmd lets \
                --bash ${./completions/lets.bash} \
                --zsh ${./completions/lets.zsh} \
                --fish ${./completions/lets.fish}
              install -Dm644 ${./completions/lets.nu} \
                "$out/share/lets/completions/lets.nu"
            '';
      };

      lib = {
        inherit
          mkTask
          mkTasks
          mkOutputs
          loadTasks
          mkBaseTasks
          ;
        mkLets = args: mkLets (args // { inherit version; });
        mkFlake = args: mkFlake (args // { inherit version; });
      };

      flakeModules.default = import ./lib/flakeModule.nix version;

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

          # Log helpers: the level word is colored by severity; the message stays
          # plain (the reset closes before the colon).
          for spec in "ERROR 31" "WARN 33" "INFO 32" "DEBUG 34" "TRACE 36"; do
            level=''${spec%% *}
            code=''${spec##* }
            want="$esc$code""m$level$esc""0m: "
            case $forced in
            *"$want"*) echo "✅ $level colored ($code) when forced" ;;
            *)
              echo "❌ expected colored $level ($code) when forced" >&2
              exit 1
              ;;
            esac
            case $plain in
            *"$level: "*) echo "✅ $level plain when not a tty" ;;
            *)
              echo "❌ expected '$level: ' in plain output" >&2
              exit 1
              ;;
            esac
          done

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
              failuresJson = builtins.toJSON (
                pkgs.lib.runTests (
                  import ./tests/mkTask.nix { inherit pkgs; } // import ./tests/mkCompletions.nix { inherit pkgs; }
                )
              );
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
        examples =
          pkgs.runCommand "check-examples"
            {
              nativeBuildInputs = [ pkgs.jq ];
              casesJson = builtins.toJSON (import ./tests/build-examples.nix { inherit pkgs; });
            }
            ''
              fail=0
              total=0
              report=""
              while read -r c; do
                total=$((total + 1))
                name=$(jq -r '.name' <<<"$c")
                bin=$(jq -r '.bin' <<<"$c")
                expStatus=$(jq -r '.status' <<<"$c")
                hasOut=$(jq -r 'if .stdout == null then "no" else "yes" end' <<<"$c")
                expOut=$(jq -r '.stdout // ""' <<<"$c")
                mapfile -t argv < <(jq -r '.args[]?' <<<"$c")
                mapfile -t envv < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' <<<"$c")
                mapfile -t unsetv < <(jq -r '.unset[]?' <<<"$c")
                unsetargs=()
                for u in "''${unsetv[@]}"; do unsetargs+=(-u "$u"); done
                if actual=$(env "''${unsetargs[@]}" "''${envv[@]}" "$bin" "''${argv[@]}" 2>/dev/null); then
                  code=0
                else
                  code=$?
                fi
                ok=1
                [ "$code" = "$expStatus" ] || ok=0
                if [ "$hasOut" = yes ] && [ "$actual" != "$expOut" ]; then ok=0; fi
                if [ "$ok" = 1 ]; then
                  report+="  ✅ $name"$'\n'
                else
                  report+="  ❌ $name (exit $code, got: $actual)"$'\n'
                  fail=1
                fi
              done < <(jq -c '.[]' <<<"$casesJson")

              if [ "$fail" = 0 ]; then
                report+="✅ $total example case(s) passed"$'\n'
                printf '%s' "$report" >"$out"
              else
                printf '%s' "$report" >&2
                echo "❌ example assertions failed" >&2
                exit 1
              fi
            '';
        completions =
          let
            fixtureLets = import ./tests/fixture-lets.nix { inherit pkgs; };
            L = "${fixtureLets}/bin/lets";
          in
          pkgs.runCommand "check-completions"
            {
              nativeBuildInputs = [
                pkgs.bashInteractive
                pkgs.zsh
                pkgs.fish
                pkgs.nushell
              ];
            }
            ''
              export HOME="$TMPDIR"
              fail=0

              echo "bash"
              bash ${./tests/bash-complete.sh} ${L} ${./completions/lets.bash} || fail=1
              echo "zsh"
              zsh ${./tests/zsh-complete.zsh} ${L} ${./completions/lets.zsh} || fail=1
              echo "fish"
              fish ${./tests/fish-complete.fish} ${L} ${./completions/lets.fish} || fail=1
              echo "nushell"
              bash ${./tests/nu-complete.sh} ${L} ${./completions/lets.nu} || fail=1

              if [ "$fail" = 0 ]; then
                touch "$out"
              else
                echo "❌ completion assertions failed" >&2
                exit 1
              fi
            '';
        flake-parts-module =
          let
            fp = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } {
              systems = [ system ];
              imports = [ self.flakeModules.default ];
              perSystem.lets.tasks = ./tasks;
            };
          in
          pkgs.runCommand "check-flake-parts-module" { } ''
            test -x ${fp.packages.${system}.lets}/bin/lets
            echo "✅ flake-parts module produces the lets binary"
            touch "$out"
          '';
        devshell-composition =
          let
            vanilla = self.lib.mkFlake {
              inherit nixpkgs;
              systems = [ system ];
              tasks = ./tasks;
            };
            fpBase = {
              systems = [ system ];
              imports = [ self.flakeModules.default ];
            };
            fpCreate = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } (
              fpBase // { perSystem.lets.tasks = ./tasks; }
            );
            fpAugment = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } (
              fpBase
              // {
                perSystem =
                  { config, pkgs, ... }:
                  {
                    lets.tasks = ./tasks;
                    devShells.default = pkgs.mkShell {
                      inputsFrom = [ config.lets.devShell ];
                      packages = [ pkgs.hello ];
                    };
                  };
              }
            );
            names = drv: map (d: d.name or "") drv.nativeBuildInputs;
            hasPkg = prefix: drv: builtins.any (pkgs.lib.hasPrefix prefix) (names drv);
            completes = drv: pkgs.lib.hasInfix "lets.bash" (drv.shellHook or "");
            results = {
              vanilla_exposes_lets_handle = vanilla.devShells.${system} ? lets;
              vanilla_default_has_lets = hasPkg "lets" vanilla.devShells.${system}.default;
              vanilla_lets_completes = completes vanilla.devShells.${system}.lets;
              fp_create_has_lets = hasPkg "lets" fpCreate.devShells.${system}.default;
              fp_create_completes = completes fpCreate.devShells.${system}.default;
              fp_augment_has_lets = hasPkg "lets" fpAugment.devShells.${system}.default;
              fp_augment_keeps_user_pkg = hasPkg "hello" fpAugment.devShells.${system}.default;
              fp_augment_completes = completes fpAugment.devShells.${system}.default;
            };
            failures = builtins.attrNames (pkgs.lib.filterAttrs (_: v: !v) results);
          in
          pkgs.runCommand "check-devshell-composition" { failuresJson = builtins.toJSON failures; } ''
            if [ "$failuresJson" = "[]" ]; then
              echo "✅ devshell augment-or-create holds (vanilla + flake-parts)"
              touch "$out"
            else
              echo "❌ devshell composition failures: $failuresJson" >&2
              exit 1
            fi
          '';
        composition =
          let
            sharedLib =
              { mkTask, ... }:
              {
                deploy = mkTask {
                  description = "Deploy (from a shared task library)";
                  run = ''echo "deploy: shared"'';
                };
              };
            consumer = self.lib.mkFlake {
              inherit nixpkgs;
              systems = [ system ];
              tasks =
                scope:
                (sharedLib scope)
                // {
                  build = scope.mkTask {
                    description = "Build (local to the project)";
                    run = ''echo "build: local"'';
                  };
                };
            };
            apps = consumer.apps.${system};
          in
          pkgs.runCommand "check-composition" { } ''
            got="$(${apps.deploy.program})"
            if [ "$got" != "deploy: shared" ]; then
              echo "❌ merged shared library task did not run: $got" >&2
              exit 1
            fi
            echo "✅ consumer runs the merged shared library task"

            if ${apps.help.program} | grep -q deploy; then
              echo "✅ shared library task is listed in help"
            else
              echo "❌ shared library task missing from help" >&2
              exit 1
            fi

            touch "$out"
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
            shellcheck = {
              enable = true;
              excludes = [ "\\.zsh$" ];
            };
            shfmt = {
              enable = true;
              settings.indent = 2;
              excludes = [ "\\.zsh$" ];
            };
            statix.enable = true;
            typos.enable = true;
          };
        };
      };
    };
}
