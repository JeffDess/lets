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
            run = ''echo "''${DB-unset}"'';
          };
          plain_two = mkTask {
            description = "Print DB and OTHER";
            run = ''echo "''${DB-unset} ''${OTHER-unset}"'';
          };
          plain_env_files = mkTask {
            description = "Print LETS_ENV_FILES as a task sees it";
            run = ''echo "''${LETS_ENV_FILES-unset}"'';
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
          parent_cd = runs "plain" "mkdir -p sub && cd sub &&";
          parent_pinned = runs "dev_loader" "load_env .prod.env;";
          parent_override = runs "plain" "load_env --override .prod.env;";
          dev_override = printAfter "load_env --override .dev.env";
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
        expect "${label}: LETS_ENV_FILES loads after envFiles" prod \
          env LETS_ENV_FILES=.prod.env ${apps.plain.program}
        expect "${label}: LETS_ENV_FILES wins over the shell" prod \
          env DB=shell LETS_ENV_FILES=.prod.env ${apps.plain.program}
        expect "${label}: LETS_ENV_FILES entries apply in order" dev \
          env LETS_ENV_FILES=.prod.env:.dev.env ${apps.plain.program}
        expect "${label}: empty LETS_ENV_FILES entries are skipped" prod \
          env LETS_ENV_FILES=:.prod.env:: ${apps.plain.program}
        expect "${label}: LETS_NO_ENV_FILES skips envFiles" unset \
          env LETS_NO_ENV_FILES=1 ${apps.plain.program}
        expect "${label}: LETS_NO_ENV_FILES keeps LETS_ENV_FILES" prod \
          env LETS_NO_ENV_FILES=1 LETS_ENV_FILES=.prod.env ${apps.plain.program}
        expect "${label}: LETS_NO_ENV_FILES keeps -E files" prod \
          env LETS_NO_ENV_FILES=1 LETS_ENV_SOURCES="file:$PWD/.prod.env" \
          ${apps.plain.program}
        expect "${label}: -E wins over LETS_ENV_FILES" prod \
          env LETS_ENV_FILES=.dev.env LETS_ENV_SOURCES="file:$PWD/.prod.env" \
          ${apps.plain.program}
        expect "${label}: LETS_ENV_FILES expands ~/" prod \
          env HOME="$PWD" LETS_ENV_FILES='~/.prod.env' ${apps.plain.program}
        expect "${label}: -E expands ~/" prod \
          env HOME="$PWD" LETS_ENV_SOURCES='file:~/.prod.env' ${apps.plain.program}
        if env LETS_ENV_SOURCES='file:$LETS_UNSET_VAR/x.env' ${apps.plain.program} \
          2>unset.err; then
          echo "❌ ${label}: an unset variable in -E should fail" >&2
          exit 1
        fi
        has_err unset.err 'LETS_UNSET_VAR is not set (from --env-file)'
        if env LETS_EMPTY_VAR= LETS_ENV_FILES='$LETS_EMPTY_VAR/.prod.env' \
          ${apps.plain.program} 2>empty.err; then
          echo "❌ ${label}: an empty variable in LETS_ENV_FILES should fail" >&2
          exit 1
        fi
        has_err empty.err 'LETS_EMPTY_VAR is empty (from LETS_ENV_FILES)'
        echo "✅ ${label}: an unset or empty variable in -E fails"
        expect "${label}: LETS_ENV_FILES reaches the child" prod \
          env LETS_ENV_FILES=.prod.env ${apps.parent_loader.program}
        expect "${label}: LETS_ENV_FILES wins over a parent export" prod \
          env LETS_ENV_FILES=.prod.env ${apps.parent_export.program}
        expect "${label}: LETS_ENV_FILES resolves from the first task's directory" \
          prod env LETS_ENV_FILES=.prod.env ${apps.parent_cd.program}
        expect "${label}: LETS_ENV_FILES survives a task's load_env" prod \
          env LETS_ENV_FILES=.prod.env ${apps.dev_loader.program}
        expect "${label}: load_env --override cannot beat the CLI" prod \
          env LETS_ENV_FILES=.prod.env ${apps.dev_override.program}
        expect "${label}: load_env --override cannot beat -E" prod \
          env LETS_ENV_SOURCES="file:$PWD/.prod.env" ${apps.dev_override.program}
        expect "${label}: LETS_ENV_SOURCES applies in order" dev \
          env LETS_ENV_SOURCES=$'file:.prod.env\nfile:.dev.env' \
          ${apps.plain.program}
        if env LETS_ENV_FILES='$LETS_UNSET_VAR/x.env' ${apps.plain.program} \
          2>unset.err; then
          echo "❌ ${label}: an unset variable in LETS_ENV_FILES should fail" >&2
          exit 1
        fi
        has_err unset.err 'LETS_UNSET_VAR is not set (from LETS_ENV_FILES)'
        echo "✅ ${label}: an unset variable in an explicit entry fails"
        if env LETS_ENV_FILES='$(: >pwned).env' ${apps.plain.program} \
          2>subst.err; then
          echo "❌ ${label}: command substitution in LETS_ENV_FILES should fail" >&2
          exit 1
        fi
        has_err subst.err 'only $VAR and ''${VAR} are expanded (from LETS_ENV_FILES)'
        if [ -e pwned ]; then
          echo "❌ ${label}: command substitution in LETS_ENV_FILES was executed" >&2
          exit 1
        fi
        echo "✅ ${label}: LETS_ENV_FILES only expands variables"
        if env LETS_ENV_FILES=.bad.env ${apps.plain.program} 2>bad.err; then
          echo "❌ ${label}: a malformed LETS_ENV_FILES entry should fail" >&2
          exit 1
        fi
        has_err bad.err ".bad.env:1: missing '=' (from LETS_ENV_FILES)"
        if env LETS_ENV_SOURCES="file:$PWD/.bad.env" ${apps.plain.program} \
          2>bad.err; then
          echo "❌ ${label}: a malformed -E file should fail" >&2
          exit 1
        fi
        has_err bad.err ".bad.env:1: missing '=' (from --env-file)"
        echo "✅ ${label}: errors name the CLI source"
        expect "${label}: a file cannot set LETS_ENV_FILES" "$PWD/.prod.env" \
          env LETS_ENV_FILES=.prod.env ${apps.plain_env_files.program}
        env LETS_ENV_FILES=.prod.env ${apps.plain_env_files.program} \
          2>reserved.err >/dev/null
        has_err reserved.err 'LETS_ENV_FILES is reserved, skipped'
        has_err reserved.err 'LETS_NO_ENV_FILES is reserved, skipped'
        has_err reserved.err 'LETS_ENV_SOURCES is reserved, skipped'
        has_err reserved.err 'LETS_ENV_VARS is reserved, skipped'
        if env LETS_ENV_FILES=.nope.env ${apps.plain.program} \
          2>missing.err; then
          echo "❌ ${label}: a missing LETS_ENV_FILES entry should fail" >&2
          exit 1
        fi
        has_err missing.err 'nope.env not found (from LETS_ENV_FILES)'
        if env LETS_ENV_SOURCES="file:$PWD/.nope.env" ${apps.plain.program} \
          2>missing.err; then
          echo "❌ ${label}: a missing -E file should fail" >&2
          exit 1
        fi
        has_err missing.err 'nope.env not found (from --env-file)'
        mkdir -p locked
        printf 'DB=x\n' >locked/.env
        chmod 000 locked
        if env LETS_ENV_SOURCES="file:$PWD/locked/.env" ${apps.plain.program} \
          2>locked.err; then
          echo "❌ ${label}: a -E file in a locked directory should fail" >&2
          exit 1
        fi
        chmod 700 locked
        has_err locked.err 'locked/.env is not a readable file (from --env-file)'
        echo "✅ ${label}: a missing LETS_ENV_FILES entry fails the task"
        expect "${label}: LETS_ENV_VARS wins over everything" cli \
          env DB=shell LETS_ENV_FILES=.prod.env LETS_ENV_VARS=DB=cli \
          ${apps.plain.program}
        expect "${label}: LETS_ENV_VARS beats a child's load_env" cli \
          env LETS_ENV_VARS=DB=cli ${apps.parent_loader.program}
        expect "${label}: LETS_ENV_VARS wins over -E" cli \
          env LETS_ENV_SOURCES="file:$PWD/.prod.env" LETS_ENV_VARS=DB=cli \
          ${apps.plain.program}
        expect "${label}: LETS_ENV_VARS keeps '=' in values" "a=b" \
          env LETS_ENV_VARS='DB=a=b' ${apps.plain.program}
        if env LETS_ENV_VARS='DB s3cr3t=x' ${apps.plain.program} 2>name.err; then
          echo "❌ ${label}: an invalid LETS_ENV_VARS name should fail" >&2
          exit 1
        fi
        has_err name.err 'LETS_ENV_VARS:1: invalid variable name'
        if grep -q s3cr3t name.err; then
          echo "❌ ${label}: an invalid LETS_ENV_VARS entry was printed" >&2
          exit 1
        fi
        echo "✅ ${label}: an invalid LETS_ENV_VARS name fails without being printed"
        expect "${label}: LETS_ENV_VARS takes one entry per line" "cli two" \
          env LETS_ENV_VARS=$'DB=cli\nOTHER=two' ${apps.plain_two.program}
        : >DB=glob
        expect "${label}: LETS_ENV_VARS values are not globbed" "*" \
          env LETS_ENV_VARS='DB=*' ${apps.plain.program}
        rm DB=glob
        if env LETS_ENV_VARS=NOEQUALS ${apps.plain.program} 2>vars.err; then
          echo "❌ ${label}: a malformed LETS_ENV_VARS entry should fail" >&2
          exit 1
        fi
        has_err vars.err "LETS_ENV_VARS:1: missing '='"
        if env LETS_ENV_VARS=$'DB=1\n\nNOEQUALS' ${apps.plain.program} 2>vars.err; then
          echo "❌ ${label}: a malformed LETS_ENV_VARS line should fail" >&2
          exit 1
        fi
        has_err vars.err "LETS_ENV_VARS:3: missing '='"
        expect "${label}: the last LETS_ENV_VARS entry wins" two \
          env LETS_ENV_VARS=$'DB=one\nDB=two' ${apps.plain.program}
        if env LETS_ENV_SOURCES=bogus ${apps.plain.program} 2>sources.err; then
          echo "❌ ${label}: a bad LETS_ENV_SOURCES entry should fail" >&2
          exit 1
        fi
        has_err sources.err "bad LETS_ENV_SOURCES entry 'bogus'"
        echo "✅ ${label}: a malformed LETS_ENV_VARS entry fails the task"
        expect "${label}: LETS_ENV_VARS survives a task's load_env" cli \
          env LETS_ENV_VARS=DB=cli ${apps.loader.program}
        expect "${label}: LETS_ENV_VARS survives load_env --override" cli \
          env LETS_ENV_VARS=DB=cli ${apps.dev_override.program}
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
      has_err() {
        grep -qF -- "$2" "$1" || {
          echo "❌ expected '$2' in $1, got: $(<"$1")" >&2
          exit 1
        }
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

      printf 'DB=local\nLETS_ENV_FILES=x\nLETS_NO_ENV_FILES=1\nLETS_ENV_SOURCES=x\n' >>.env
      printf 'LETS_ENV_VARS=DB=injected\n' >>.env
      printf 'DB=prod\n' >.prod.env
      printf 'BROKEN\n' >.bad.env
      printf 'DB=dev\n' >.dev.env
      ${composed "vanilla" vanilla.apps.${system}}
      ${composed "flake-parts" fp.apps.${system}}
      echo "✅ env precedence holds across composed tasks (vanilla + flake-parts)"

      mkdir 'dollar$dir'
      cd 'dollar$dir'
      if env LETS_ENV_FILES=.prod.env ${vanilla.apps.${system}.plain.program} \
        2>dollar.err; then
        echo "❌ a relative LETS_ENV_FILES entry under a \$ directory should fail" >&2
        exit 1
      fi
      has_err dollar.err "cannot resolve .prod.env: $PWD contains '\$'"
      cd ..
      echo "✅ a relative LETS_ENV_FILES entry under a \$ directory fails"

      mkdir 'colon:dir'
      cd 'colon:dir'
      if env LETS_ENV_FILES=.prod.env ${vanilla.apps.${system}.plain.program} \
        2>colon.err; then
        echo "❌ a relative LETS_ENV_FILES entry under a : directory should fail" >&2
        exit 1
      fi
      has_err colon.err "cannot resolve .prod.env: $PWD contains '\$' or ':'"
      cd ..
      echo "✅ a relative LETS_ENV_FILES entry under a : directory fails"

      mkdir -p e2e/bin e2e/apps e2e/sub
      touch e2e/flake.nix
      printf 'DB=local\n' >e2e/.env
      printf 'DB=cli\n' >e2e/sub/.cli.env
      ln -s ${vanilla.apps.${system}.plain.program} e2e/apps/plain
      ln -s ${vanilla.apps.${system}.parent_export.program} e2e/apps/parent_export
      printf '#!%s\nexec "$LETS_TEST_APPS/''${5#.#}" "''${@:7}"\n' ${pkgs.runtimeShell} \
        >e2e/bin/nix
      chmod +x e2e/bin/nix
      cd e2e/sub
      export LETS_TEST_APPS="$PWD/../apps"
      lets="${vanilla.packages.${system}.lets}/bin/lets"
      PATH="$PWD/../bin:$PATH" expect "lets -E reaches the task" cli \
        "$lets" -E .cli.env plain
      PATH="$PWD/../bin:$PATH" expect "lets -E reaches a child task" cli \
        "$lets" -E .cli.env parent_export
      PATH="$PWD/../bin:$PATH" expect "LETS_ENV_FILES resolves from the caller" cli \
        env LETS_ENV_FILES=.cli.env "$lets" plain
      PATH="$PWD/../bin:$PATH" expect "lets runs tasks from the project root" local \
        "$lets" plain
      unset LETS_TEST_APPS
      cd ../..
      echo "✅ the lets wrapper hands CLI files to tasks"

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
      err="$(env CALLER_TOKEN=c4llersecret LETS_ENV_VARS=VAR_TOKEN=v4rsecret \
        ${pkgs.bash}/bin/bash -x ${vanilla.apps.${system}.quiet.program} 2>&1)"
      mv .env.bak .env
      if [[ $err == *f1lesecret* || $err == *c4llersecret* || $err == *v4rsecret* ]]; then
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
      empty_err="$(env HOME="$PWD/home" LETS_TEST_DIR= ${expand} 2>&1 >/dev/null)"
      case "$empty_err" in
      *"LETS_TEST_DIR is empty, skipped"*) ;;
      *)
        echo "❌ an empty variable in an envFiles entry should warn: $empty_err" >&2
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
