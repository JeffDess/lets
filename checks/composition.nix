{
  pkgs,
  system,
  self,
  nixpkgs,
  flake-parts,
}:
{
  flake-parts-module =
    let
      fp = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } {
        systems = [ system ];
        imports = [ self.flakeModules.default ];
        perSystem.lets.tasks = ../tasks;
      };
    in
    pkgs.runCommand "check-flake-parts-module" { } ''
      test -x ${fp.packages.${system}.lets}/bin/lets
      test -x ${fp.packages.${system}.default}/bin/lets
      echo "✅ flake-parts module produces the lets binary (and a default)"
      touch "$out"
    '';
  devshell-composition =
    let
      vanilla = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        tasks = ../tasks;
      };
      fpBase = {
        systems = [ system ];
        imports = [ self.flakeModules.default ];
      };
      fpCreate = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } (
        fpBase // { perSystem.lets.tasks = ../tasks; }
      );
      fpAugment = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } (
        fpBase
        // {
          perSystem =
            { config, pkgs, ... }:
            {
              lets.tasks = ../tasks;
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

      help_out="$(${apps.help.program})"
      case "$help_out" in
      *deploy*) echo "✅ shared library task is listed in help" ;;
      *)
        echo "❌ shared library task missing from help" >&2
        exit 1
        ;;
      esac

      touch "$out"
    '';
  env-files =
    let
      envTasks =
        { mkTask, tasks, ... }:
        let
          printAfter =
            setup:
            mkTask {
              description = "Print DB after: ${setup}";
              run = "${setup}; echo \"$DB\"";
            };
          runs =
            child: setup:
            mkTask {
              description = "Run ${child} after: ${setup}";
              runtimeInputs = [ tasks.${child}.app ];
              run = "${setup} ${child}";
            };
        in
        {
          greet = mkTask {
            description = "Greet from env files";
            args.name = {
              short = "n";
              default = [
                "$GREET_NAME"
                "nobody"
              ];
            };
            args.loud = {
              type = "flag";
              short = "l";
            };
            run = ''echo "$name $GREET_SOURCE"'';
          };
          hosted = mkTask {
            description = "Print a host given with -h";
            args.host.short = "h";
            run = ''echo "$host"'';
          };
          plain = mkTask {
            description = "Print DB without loading anything";
            run = ''echo "$DB"'';
          };
          shell_state = mkTask {
            description = "Print whether loading env files left the shell options as they were";
            run = ''
              if [[ $IFS == $' \t\n' && $- != *f* ]]; then echo clean; else echo changed; fi
            '';
          };
          traced = printAfter "set -x; load_env .traced.env; set +x";
          quiet = mkTask {
            description = "Load envFiles and print nothing";
            run = "true";
          };
          loader = printAfter "load_env .prod.env";
          dev_loader = printAfter "load_env .dev.env";
          parent_loader = runs "loader" "";
          parent_profile = runs "plain" "load_env .prod.env;";
          parent_assign = runs "plain" "DB=x";
          parent_export = runs "plain" "export DB=x;";
          parent_pinned = runs "dev_loader" "load_env .prod.env;";
          parent_override = runs "plain" "load_env --override .prod.env;";
        };
      vanilla = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [ ".env" ];
        tasks = envTasks;
      };
      fp = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } {
        systems = [ system ];
        imports = [ self.flakeModules.default ];
        perSystem.lets = {
          tasks = envTasks;
          envFiles = [ ".env" ];
        };
      };
      composed = label: apps: ''
        expect "${label}: loader run directly" prod ${apps.loader.program}
        expect "${label}: shell value equal to envFiles is a file value" prod \
          env DB=local ${apps.loader.program}
        expect "${label}: parent runs loader" prod ${apps.parent_loader.program}
        expect "${label}: caller env wins in child" shell \
          env DB=shell ${apps.parent_loader.program}
        expect "${label}: parent profile reaches child" prod ${apps.parent_profile.program}
        expect "${label}: parent assignment reaches child" x ${apps.parent_assign.program}
        expect "${label}: parent export reaches child" x ${apps.parent_export.program}
        expect "${label}: parent override reaches child" prod \
          env DB=shell ${apps.parent_override.program}
        expect "${label}: parent profile wins over child profile" prod \
          ${apps.parent_pinned.program}
      '';
      layered = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [
          ".env"
          ".local.env"
        ];
        tasks = envTasks;
      };
      layeredApps = layered.apps.${system};
      nested = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [ "conf/.env" ];
        tasks = envTasks;
      };
      expandTasks =
        { mkTask, ... }:
        {
          expand = mkTask {
            description = "Print values loaded from expanded envFiles entries";
            run = ''
              echo "''${FROM_HOME:-no} ''${FROM_TILDE:-no} ''${FROM_BRACED:-no} ''${FROM_PLAIN:-no}"
            '';
          };
        };
      expanding = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [
          "$HOME/home.env"
          "~/tilde.env"
          "\${LETS_TEST_DIR}/braced.env"
          "$LETS_TEST_DIR/plain.env"
          "`: >pwned`.env"
          "trailing\\"
          "it’s.env"
        ];
        tasks = expandTasks;
      };
      expand = expanding.apps.${system}.expand.program;
    in
    pkgs.runCommand "check-env-files" { } ''
      expect() {
        local label="$1" want="$2" got
        shift 2
        got="$("$@")" || {
          echo "❌ $label: exited $?" >&2
          exit 1
        }
        if [ "$got" != "$want" ]; then
          echo "❌ $label: expected $want, got $got" >&2
          exit 1
        fi
      }

      printf 'GREET_NAME=Alice\nGREET_SOURCE=file\nname=fromfile\n' >.env
      for prog in \
        ${vanilla.apps.${system}.greet.program} \
        ${fp.apps.${system}.greet.program}; do
        expect "envFiles load before arg parsing" "Alice file" "$prog"
        expect "arguments keep their parsed value" "Bob file" "$prog" --name Bob
        expect "caller env wins over envFiles" "Alice shell" \
          env GREET_SOURCE=shell "$prog"
        "$prog" 2>&1 >/dev/null | grep -qF "name is reserved, skipped" || {
          echo "❌ an envFiles key named like an argument should be skipped" >&2
          exit 1
        }
      done
      echo "✅ envFiles load before arg parsing (vanilla + flake-parts)"

      printf 'DB=local\n' >>.env
      printf 'DB=prod\n' >.prod.env
      printf 'DB=dev\n' >.dev.env
      ${composed "vanilla" vanilla.apps.${system}}
      ${composed "flake-parts" fp.apps.${system}}
      echo "✅ env precedence holds across composed tasks (vanilla + flake-parts)"

      expect "loading env files keeps the shell options" clean \
        ${vanilla.apps.${system}.shell_state.program}
      echo "✅ loading env files keeps the shell options"

      expect "an empty caller value wins over envFiles" "" \
        env DB= ${vanilla.apps.${system}.plain.program}
      echo "✅ an empty caller value wins over envFiles"

      printf 'DB=s3cr3t\n' >.traced.env
      expect "load_env under set -x" s3cr3t ${vanilla.apps.${system}.traced.program}
      err="$(${vanilla.apps.${system}.traced.program} 2>&1 >/dev/null)"
      if [[ $err == *s3cr3t* ]]; then
        echo "❌ load_env traced a value under set -x: $err" >&2
        exit 1
      fi
      cp .env .env.bak
      printf 'TOKEN=f1lesecret\n' >>.env
      err="$(env CALLER_TOKEN=c4llersecret \
        ${pkgs.bash}/bin/bash -x ${vanilla.apps.${system}.quiet.program} 2>&1)"
      mv .env.bak .env
      if [[ $err == *f1lesecret* || $err == *c4llersecret* ]]; then
        echo "❌ envFiles traced a value under bash -x: $err" >&2
        exit 1
      fi
      echo "✅ loading env files never traces values"

      mkdir layers
      cd layers
      printf 'DB=local\n' >.env
      printf 'DB=other\n' >.local.env
      printf 'DB=prod\n' >.prod.env
      expect "later envFiles entry wins" other ${layeredApps.plain.program}
      expect "shell value equal to the last envFiles value is a file value" prod \
        env DB=other ${layeredApps.loader.program}
      expect "shell value equal to an overridden envFiles value wins" local \
        env DB=local ${layeredApps.loader.program}
      cd ..
      echo "✅ envFiles entries load in order"

      mkdir home dir
      printf 'FROM_HOME=1\n' >home/home.env
      printf 'FROM_TILDE=1\n' >home/tilde.env
      printf 'FROM_BRACED=1\n' >dir/braced.env
      printf 'FROM_PLAIN=1\n' >dir/plain.env
      expect "envFiles entries expand ~/ and variables" "1 1 1 1" \
        env HOME="$PWD/home" LETS_TEST_DIR="$PWD/dir" ${expand}
      if [ -e pwned ]; then
        echo "❌ command substitution in an envFiles entry was executed" >&2
        exit 1
      fi
      err="$(env HOME="$PWD/home" ${expand} 2>&1 >/dev/null)"
      case "$err" in
      *"LETS_TEST_DIR is not set, skipped"*) ;;
      *)
        echo "❌ an unset variable in an envFiles entry should warn: $err" >&2
        exit 1
        ;;
      esac
      echo "✅ envFiles entries expand ~/ and variables, nothing else"

      case "$err" in
      *"pwned\`.env not found, skipped"*) ;;
      *)
        echo "❌ a missing envFiles entry should warn: $err" >&2
        exit 1
        ;;
      esac
      echo "✅ missing envFiles are skipped with a warning"

      mkdir broken
      cd broken
      printf 'BROKEN\n' >.env
      for prog in \
        ${vanilla.apps.${system}.greet.program} \
        ${fp.apps.${system}.greet.program}; do
        for args in --help -h "--name=x --help" "--loud --help" -lh "-n x -h"; do
          # shellcheck disable=SC2086
          help="$("$prog" $args)" || {
            echo "❌ greet $args should not load envFiles" >&2
            exit 1
          }
          case "$help" in
          "Usage: greet"*) ;;
          *)
            echo "❌ greet $args printed: $help" >&2
            exit 1
            ;;
          esac
        done
        for args in "--name --help" "-n --help" -nh "-- --help"; do
          # shellcheck disable=SC2086
          if err="$("$prog" $args 2>&1 >/dev/null)"; then
            echo "❌ greet $args should load envFiles" >&2
            exit 1
          fi
          case "$err" in
          *".env:1: missing '=' (from envFiles)"*) ;;
          *)
            echo "❌ greet $args failed with: $err" >&2
            exit 1
            ;;
          esac
        done
      done
      if err="$(${vanilla.apps.${system}.hosted.program} -h x 2>&1 >/dev/null)"; then
        echo "❌ hosted -h x should load envFiles" >&2
        exit 1
      fi
      case "$err" in
      *".env:1: missing '=' (from envFiles)"*) ;;
      *)
        echo "❌ hosted -h x failed with: $err" >&2
        exit 1
        ;;
      esac
      help="$(${vanilla.apps.${system}.hosted.program} --help)" || {
        echo "❌ hosted --help should not load envFiles" >&2
        exit 1
      }
      case "$help" in
      "Usage: hosted"*) ;;
      *)
        echo "❌ hosted --help printed: $help" >&2
        exit 1
        ;;
      esac
      cd ..
      echo "✅ --help prints usage without loading envFiles"

      mkdir dangling
      cd dangling
      ln -s nowhere .env
      if err="$(${vanilla.apps.${system}.plain.program} 2>&1 >/dev/null)"; then
        echo "❌ a broken envFiles symlink should fail the task" >&2
        exit 1
      fi
      case "$err" in
      *".env is a broken symlink (from envFiles)"*) ;;
      *)
        echo "❌ a broken envFiles symlink failed with: $err" >&2
        exit 1
        ;;
      esac
      cd ..
      echo "✅ a broken envFiles symlink fails the task"

      mkdir dir-env
      cd dir-env
      mkdir .env
      if err="$(${vanilla.apps.${system}.plain.program} 2>&1 >/dev/null)"; then
        echo "❌ an envFiles directory should fail the task" >&2
        exit 1
      fi
      case "$err" in
      *".env is not a readable file (from envFiles)"*) ;;
      *)
        echo "❌ an envFiles directory failed with: $err" >&2
        exit 1
        ;;
      esac
      cd ..
      echo "✅ an envFiles directory fails the task"

      mkdir unreadable-env
      cd unreadable-env
      printf 'DB=x\n' >.env
      chmod 000 .env
      if err="$(${vanilla.apps.${system}.plain.program} 2>&1 >/dev/null)"; then
        echo "❌ an unreadable envFiles entry should fail the task" >&2
        exit 1
      fi
      chmod 600 .env
      case "$err" in
      *".env is not a readable file (from envFiles)"*) ;;
      *)
        echo "❌ an unreadable envFiles entry failed with: $err" >&2
        exit 1
        ;;
      esac
      expect_warn "an envFiles entry under a missing directory is skipped" unset \
        'conf/.env not found, skipped (from envFiles)' \
        ${nested.apps.${system}.plain.program}
      mkdir conf
      printf 'DB=x\n' >conf/.env
      chmod 000 conf
      if err="$(${nested.apps.${system}.plain.program} 2>&1 >/dev/null)"; then
        echo "❌ an envFiles entry in a locked directory should fail the task" >&2
        exit 1
      fi
      chmod 700 conf
      case "$err" in
      *"conf/.env is not a readable file (from envFiles)"*) ;;
      *)
        echo "❌ an envFiles entry in a locked directory failed with: $err" >&2
        exit 1
        ;;
      esac
      cd ..
      echo "✅ unreadable envFiles entries fail the task"

      touch "$out"
    '';
}
