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
  consumer-isolation =
    let
      forced = throw "lets' nixpkgs was forced";
      sealed = (import ../flake.nix).outputs {
        self = sealed // {
          inherit (self) outPath;
          inputs = {
            inherit flake-parts;
            nixpkgs = forced;
          };
        };
        inherit flake-parts;
        nixpkgs = forced;
      };
      consumerSelf = {
        inherit (self) outPath;
        inputs = consumerInputs;
      };
      consumerInputs = {
        self = consumerSelf;
        inherit nixpkgs;
      };
      fp = flake-parts.lib.mkFlake { inputs = consumerInputs; } {
        systems = [ system ];
        imports = [ sealed.flakeModules.default ];
        perSystem.lets.tasks = ../tasks;
      };
      vanilla = sealed.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        tasks = ../tasks;
      };
      tasks = sealed.lib.mkBaseTasks { inherit pkgs; };
      greet = (sealed.lib.mkTask { inherit pkgs; }) {
        description = "Say hello";
        run = "echo hello";
      };
      lock = builtins.fromJSON (builtins.readFile ../flake.lock);
      evaluates = v: (builtins.tryEval (builtins.deepSeq v true)).success;
      results = {
        mk_task = evaluates (greet.__build "greet").app.drvPath;
        mk_tasks = evaluates (sealed.lib.mkTasks { inherit greet; }).greet.app.drvPath;
        load_tasks =
          evaluates
            (sealed.lib.loadTasks {
              inherit pkgs;
              src = ../tasks;
            }).demo.app.drvPath;
        mk_base_tasks = evaluates tasks.demo.app.drvPath;
        mk_outputs = evaluates (sealed.lib.mkOutputs { inherit pkgs tasks; }).packages.demo.drvPath;
        mk_lets = evaluates (sealed.lib.mkLets { inherit pkgs tasks; }).drvPath;
        flake_module_package = evaluates fp.packages.${system}.lets.drvPath;
        flake_module_dev_shell = evaluates fp.devShells.${system}.default.drvPath;
        mk_flake_package = evaluates vanilla.packages.${system}.lets.drvPath;
        mk_flake_dev_shell = evaluates vanilla.devShells.${system}.default.drvPath;
        root_inputs =
          builtins.attrNames lock.nodes.root.inputs == [
            "flake-parts"
            "nixpkgs"
          ];
        flake_parts_own_lib = builtins.isString lock.nodes.flake-parts.inputs.nixpkgs-lib;
      };
      failures = builtins.attrNames (pkgs.lib.filterAttrs (_: v: !v) results);
    in
    pkgs.runCommand "check-consumer-isolation" { failuresJson = builtins.toJSON failures; } ''
      if [ "$failuresJson" = "[]" ]; then
        echo "✅ consumers evaluate lets without its nixpkgs / its lock has no dev inputs"
        touch "$out"
      else
        echo "❌ consumer isolation failures: $failuresJson" >&2
        exit 1
      fi
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
      decoding = {
        command = "cat {}";
        runtimeInputs = _: [ ];
      };
      vanillaSecrets = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        tasks = ../tasks;
        secrets = decoding;
      };
      fpSecrets = flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } (
        fpBase
        // {
          perSystem.lets = {
            tasks = ../tasks;
            secrets = decoding;
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
        vanilla_dev_shell_has_decoder = hasPkg "lets-decoder" vanillaSecrets.devShells.${system}.default;
        fp_dev_shell_has_decoder = hasPkg "lets-decoder" fpSecrets.devShells.${system}.default;
        vanilla_without_secrets_has_no_decoder = !hasPkg "lets-decoder" vanilla.devShells.${system}.default;
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
      fakedec = pkgs.writeShellApplication {
        name = "fakedec";
        text = ''
          case "$1" in
          *empty*) exit 0 ;;
          *raw*)
            cat "$1"
            exit 0
            ;;
          *bad*)
            echo "fakedec: cannot decrypt $1" >&2
            exit 3
            ;;
          esac
          printf "DECODED='%s'\n" "$1"
          printf "SEEN='%s'\n" "''${FROM_ENV-unset}"
          cat "$1"
        '';
      };
      posdec = pkgs.writeShellApplication {
        name = "posdec";
        text = ''
          printf "ARGV='"
          printf '[%s]' "$@"
          printf "'\n"
          cat "$2"
        '';
      };
      secretsCfg = {
        command = "fakedec {}";
        runtimeInputs = _: [ fakedec ];
        pattern = ".{name}.enc.env";
      };
      positioned = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets = {
          command = "posdec --first {} --last";
          runtimeInputs = _: [ posdec ];
          pattern = ".{name}.enc.env";
        };
        tasks = envTasks;
      };
      posApps = positioned.apps.${system};
      listed = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets = {
          command = [
            "posdec"
            "--first"
            "{}"
            "--last"
            "a b"
          ];
          runtimeInputs = [ posdec ];
          pattern = ".{name}.enc.env";
        };
        tasks = envTasks;
      };
      listApps = listed.apps.${system};
      unreachable = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets.command = "fakedec {}";
        tasks = envTasks;
      };
      unreachableApps = unreachable.apps.${system};
      noexec = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets = secretsCfg // {
          command = "${pkgs.writeText "noexec" ""} {}";
        };
        tasks = envTasks;
      };
      noexecApps = noexec.apps.${system};
      strict =
        files:
        (self.lib.mkFlake {
          inherit nixpkgs;
          systems = [ system ];
          secrets = secretsCfg // {
            inherit files;
          };
          tasks = envTasks;
        }).apps.${system};
      withFiles = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [ ".env" ];
        secrets = secretsCfg // {
          files = [ "base" ];
        };
        tasks = envTasks;
      };
      withFilesApps = withFiles.apps.${system};
      lenient =
        onError:
        self.lib.mkFlake {
          inherit nixpkgs;
          systems = [ system ];
          envFiles = [ ".env" ];
          secrets = secretsCfg // {
            inherit onError;
            files = [
              "bad"
              "empty"
              "rawjunk"
              "rawblank"
              "rawnoisy"
              "rawhalf"
              "rawhalfeq"
            ];
          };
          tasks = envTasks;
        };
      warnApps = (lenient "warn").apps.${system};
      ignoreApps = (lenient "ignore").apps.${system};
      unreachableWarn = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets = {
          command = "fakedec {}";
          onError = "warn";
          files = [ "dev" ];
        };
        tasks = envTasks;
      };
      unbuilt = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        secrets = secretsCfg // {
          command = "fakedec {} unbuilt";
        };
        tasks = envTasks;
      };
      storedDrv =
        builtins.unsafeDiscardOutputDependency
          (derivation {
            name = "stored";
            inherit system;
            builder = "/bin/sh";
          }).drvPath;
      envTasks =
        { mkTask, tasks, ... }:
        let
          withFiles =
            envFiles:
            mkTask {
              description = "Print DB after loading ${toString envFiles}";
              inherit envFiles;
              run = ''echo "$DB"'';
            };
          runsWith =
            envFiles: child:
            mkTask {
              description = "Run ${child} after loading ${toString envFiles}";
              inherit envFiles;
              runtimeInputs = [ tasks.${child}.app ];
              run = child;
            };
          runs =
            child: setup:
            mkTask {
              description = "Run ${child} after: ${setup}";
              runtimeInputs = [ tasks.${child}.app ];
              run = ''
                ${setup} ${child}
              '';
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
          needs_dev = mkTask {
            description = "Always decrypts dev";
            secrets = [ "dev" ];
            args.db.default = [ "$DB" ];
            run = ''echo "$db"'';
          };
          needs_bad = mkTask {
            description = "Always decrypts a file the decoder fails on";
            secrets = [ "bad" ];
            run = ''echo "''${DB-unset}"'';
          };
          plain_argv = mkTask {
            description = "Print ARGV from the decoder";
            secrets = [ "dev" ];
            run = ''echo "''${ARGV-unset}"'';
          };
          plain_base = mkTask {
            description = "Print DB and BASE";
            run = ''echo "''${DB-unset} ''${BASE-unset}"'';
          };
          plain_decoded = mkTask {
            description = "Print DB and DECODED";
            run = ''echo "''${DB-unset} ''${DECODED-unset}"'';
          };
          plain_seen = mkTask {
            description = "Print SEEN from the decoder";
            run = ''echo "''${SEEN-unset}"'';
          };
          api_task = mkTask {
            description = "Load .api.env and print API_URL";
            envFiles = [ ".api.env" ];
            run = ''echo "$API_URL"'';
          };
          residue_dev = mkTask {
            description = "Decrypt dev and report loader residue";
            secrets = [ "dev" ];
            run = ''
              state="$(declare -p "''${!_lets@}" "''${!_LETS@}" "''${!_dotenv@}" "''${!DOTENV@}")"
              if [[ $state == *DECODED=* ]]; then
                echo residue
              else
                echo clean
              fi
            '';
          };
          prod_dev = mkTask {
            description = "Load .prod.env, decrypt dev and print DB";
            envFiles = [ ".prod.env" ];
            secrets = [ "dev" ];
            run = ''echo "$DB"'';
          };
          seen_dev = mkTask {
            description = "Decrypt dev and print SEEN";
            secrets = [ "dev" ];
            run = ''echo "''${SEEN-unset}"'';
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
          quiet = mkTask {
            description = "Load envFiles and print nothing";
            run = "true";
          };
          loader = withFiles [ ".prod.env" ];
          dev_loader = withFiles [ ".dev.env" ];
          parent_loader = runs "loader" "";
          parent_profile = runsWith [ ".prod.env" ] "plain";
          parent_assign = runs "plain" "DB=x";
          parent_export = runs "plain" "export DB=x;";
          parent_cd = runs "plain" "mkdir -p sub && cd sub &&";
          parent_cd_dev = runs "needs_dev" "mkdir -p sub && cd sub &&";
          quiet_dev = mkTask {
            description = "Decrypt dev and print nothing";
            secrets = [ "dev" ];
            run = "true";
          };
          parent_pinned = runsWith [ ".prod.env" ] "dev_loader";
          prod_or_unset = mkTask {
            description = "Load .prod.env and print DB or unset";
            envFiles = [ ".prod.env" ];
            run = ''echo "''${DB-unset}"'';
          };
          parent_prod_or_unset = runs "prod_or_unset" "";
        };
      vanilla = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [ ".env" ];
        secrets = secretsCfg;
        tasks = envTasks;
      };
      fpWith =
        secrets:
        flake-parts.lib.mkFlake { inputs = { inherit self nixpkgs; }; } {
          systems = [ system ];
          imports = [ self.flakeModules.default ];
          perSystem.lets = {
            tasks = envTasks;
            envFiles = [ ".env" ];
            inherit secrets;
          };
        };
      fp = fpWith secretsCfg;
      fpFilesApps = (fpWith (secretsCfg // { files = [ "base" ]; })).apps.${system};
      fpWarnApps =
        (fpWith (
          secretsCfg
          // {
            onError = "warn";
            files = [ "bad" ];
          }
        )).apps.${system};
      composed = label: apps: ''
        expect "${label}: loader run directly" prod ${apps.loader.program}
        expect "${label}: shell value equal to envFiles wins" local \
          env DB=local ${apps.loader.program}
        expect "${label}: parent values win over child envFiles" local \
          ${apps.parent_loader.program}
        expect "${label}: caller env wins in child" shell \
          env DB=shell ${apps.parent_loader.program}
        expect "${label}: parent profile reaches child" prod ${apps.parent_profile.program}
        expect "${label}: parent assignment reaches child" x ${apps.parent_assign.program}
        expect "${label}: parent export reaches child" x ${apps.parent_export.program}
        expect "${label}: every -e name stays pinned in a child" local \
          env LETS_ENV_VARS=$'DB=local\nOTHER=x' ${apps.parent_loader.program}
        expect "${label}: a task's secrets beat its envFiles" dev-secret \
          ${apps.prod_dev.program}
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
        expect "${label}: a parent export reaches the child over LETS_ENV_FILES" x \
          env LETS_ENV_FILES=.prod.env ${apps.parent_export.program}
        expect_warn "${label}: LETS_ENV_FILES resolves from the first task's directory" \
          prod '.env not found, skipped (from envFiles)' \
          env LETS_ENV_FILES=.prod.env ${apps.parent_cd.program}
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
        has_err bad.err ".bad.env:1: expected '=' after the name (from LETS_ENV_FILES)"
        if env LETS_ENV_SOURCES="file:$PWD/.bad.env" ${apps.plain.program} \
          2>bad.err; then
          echo "❌ ${label}: a malformed -E file should fail" >&2
          exit 1
        fi
        has_err bad.err ".bad.env:1: expected '=' after the name (from --env-file)"
        echo "✅ ${label}: errors name the CLI source"
        expect "${label}: the first task clears LETS_ENV_FILES" unset \
          env LETS_ENV_FILES=.prod.env ${apps.plain_env_files.program}
        env -C hostile LETS_ENV_FILES=.prod.env ${apps.plain_env_files.program} \
          2>reserved.err >/dev/null
        has_err reserved.err 'LETS_ENV_FILES is reserved, skipped'
        has_err reserved.err 'LETS_NO_ENV_FILES is reserved, skipped'
        has_err reserved.err 'LETS_ENV_SOURCES is reserved, skipped'
        has_err reserved.err 'LETS_ENV_VARS is reserved, skipped'
        has_err reserved.err 'LETS_SECRETS is reserved, skipped'
        expect_warn "${label}: a file cannot steer the loading" prod \
          'LETS_NO_ENV_FILES is reserved, skipped' \
          env -C hostile ${apps.loader.program}
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
        echo "✅ ${label}: missing or unreadable LETS_ENV_FILES and -E files fail the task"
        expect "${label}: LETS_ENV_VARS wins over everything" cli \
          env DB=shell LETS_ENV_FILES=.prod.env LETS_ENV_VARS=DB=cli \
          ${apps.plain.program}
        expect "${label}: LETS_ENV_VARS beats a child's envFiles" cli \
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
        expect "${label}: LETS_SECRETS decrypts through the decoder" \
          "dev-secret .dev.enc.env" \
          env LETS_SECRETS=dev ${apps.plain_decoded.program}
        expect "${label}: LETS_SECRETS wins over the shell" dev-secret \
          env DB=shell LETS_SECRETS=dev ${apps.plain.program}
        expect "${label}: LETS_SECRETS after LETS_ENV_FILES" dev-secret \
          env LETS_ENV_FILES=.prod.env LETS_SECRETS=dev ${apps.plain.program}
        expect "${label}: -E wins over LETS_SECRETS" prod \
          env LETS_SECRETS=dev LETS_ENV_SOURCES="file:$PWD/.prod.env" \
          ${apps.plain.program}
        expect "${label}: a secret name keeps '&'" amp \
          env LETS_SECRETS='a&b' ${apps.plain.program}
        if env LETS_SECRETS=dev LETS_SECRETS_DIR=/nowhere ${apps.plain.program} \
          2>dir.err; then
          echo "❌ ${label}: a missing LETS_SECRETS_DIR should fail" >&2
          exit 1
        fi
        has_err dir.err \
          'LETS_SECRETS_DIR /nowhere is not a directory (from LETS_SECRETS)'
        echo "✅ ${label}: a missing LETS_SECRETS_DIR fails the task"
        expect "${label}: LETS_SECRETS reaches the child" dev-secret \
          env LETS_SECRETS=dev ${apps.parent_loader.program}
        expect "${label}: LETS_ENV_VARS beats LETS_SECRETS" cli \
          env LETS_SECRETS=dev LETS_ENV_VARS=DB=cli ${apps.plain.program}
        expect "${label}: empty LETS_SECRETS entries are skipped" dev-secret \
          env LETS_SECRETS=:dev:: ${apps.plain.program}
        expect_warn "${label}: LETS_SECRETS decrypts from the first task's directory" \
          dev-secret '.env not found, skipped (from envFiles)' \
          env LETS_SECRETS=dev ${apps.parent_cd.program}
        expect "${label}: LETS_ENV_FILES wins over a task's secrets" prod \
          env LETS_ENV_FILES=.prod.env ${apps.needs_dev.program}
        expect "${label}: LETS_SECRETS wins over a task's secrets" prod-secret \
          env LETS_SECRETS=prod ${apps.needs_dev.program}
        expect_warn "${label}: a file cannot redirect the decoder" dev-secret \
          '_LETS_SECRET_BIN is reserved, skipped' \
          env LETS_ENV_FILES=.hijack.env LETS_SECRETS=dev ${apps.plain.program}
        env LETS_ENV_FILES=.hijack.env LETS_SECRETS=dev ${apps.plain.program} \
          2>hijack.err >/dev/null
        has_err hijack.err '_LETS_SECRET_BIN is reserved, skipped'
        has_err hijack.err 'LETS_SECRETS_DIR is reserved, skipped'
        if env LETS_ENV_VARS=_LETS_SECRET_BIN=/nowhere ${apps.plain.program} \
          2>hijack.err; then
          echo "❌ ${label}: -e should not redirect the decoder" >&2
          exit 1
        fi
        has_err hijack.err '_LETS_SECRET_BIN is reserved (from -e or LETS_ENV_VARS)'
        echo "✅ ${label}: the decoder settings are reserved"
        if env LETS_SECRETS=bad ${apps.plain.program} 2>secret.err; then
          echo "❌ ${label}: a failing decoder should fail the task" >&2
          exit 1
        fi
        has_err secret.err 'bad.enc.env failed (exit 3) (from LETS_SECRETS)'
        echo "✅ ${label}: a failing decoder fails the task"
        expect "${label}: a task's secrets load without a flag" dev-secret \
          ${apps.needs_dev.program}
        expect "${label}: a task's secrets lose to the shell" shell \
          env DB=shell ${apps.needs_dev.program}
        expect "${label}: LETS_ENV_VARS survives a task's envFiles" cli \
          env LETS_ENV_VARS=DB=cli ${apps.loader.program}
        expect "${label}: LETS_ENV_FILES survives a task's envFiles" prod \
          env LETS_ENV_FILES=.prod.env ${apps.dev_loader.program}
        expect "${label}: LETS_NO_ENV_FILES keeps LETS_SECRETS" dev-secret \
          env LETS_NO_ENV_FILES=1 LETS_SECRETS=dev ${apps.plain.program}
        expect "${label}: LETS_NO_ENV_FILES keeps a task's secrets" dev-secret \
          env LETS_NO_ENV_FILES=1 ${apps.needs_dev.program}
        expect "${label}: LETS_ENV_VARS survives a task's secrets" cli \
          env LETS_ENV_VARS=DB=cli ${apps.needs_dev.program}
        if ${apps.parent_cd_dev.program} 2>cd.err >/dev/null; then
          echo "❌ ${label}: a task's secrets should decrypt from its own directory" >&2
          exit 1
        fi
        has_err cd.err '.dev.enc.env failed (exit 1) (from secrets)'
        expect "${label}: -S then -E applies in flag order" prod \
          env LETS_ENV_SOURCES=$'secret:dev\nfile:.prod.env' \
          ${apps.plain.program}
        expect "${label}: -E then -S applies in flag order" dev-secret \
          env LETS_ENV_SOURCES=$'file:.prod.env\nsecret:dev' \
          ${apps.plain.program}
        if env LETS_ENV_FILES='$LETS_UNSET_VAR/x.env' ${apps.plain.program} \
          2>unset.err; then
          echo "❌ ${label}: an unset variable in LETS_ENV_FILES should fail" >&2
          exit 1
        fi
        has_err unset.err 'LETS_UNSET_VAR is not set (from LETS_ENV_FILES)'
        echo "✅ ${label}: an unset variable in an explicit entry fails"
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
      chained = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [
          ".conf.env"
          "$CONF_DIR/x.env"
        ];
        tasks = envTasks;
      };
      confOnly = self.lib.mkFlake {
        inherit nixpkgs;
        systems = [ system ];
        envFiles = [ ".conf.env" ];
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
    pkgs.runCommand "check-env-files" { inherit storedDrv; } ''
      expect_warn() {
        local label="$1" want="$2" warning="$3" got
        shift 3
        got="$("$@" 2>"$NIX_BUILD_TOP/expect.err")" || {
          echo "❌ $label: exited $?: $(<"$NIX_BUILD_TOP/expect.err")" >&2
          exit 1
        }
        if [ "$got" != "$want" ]; then
          echo "❌ $label: expected $want, got $got" >&2
          exit 1
        fi
        if [ -z "$warning" ] && [ -s "$NIX_BUILD_TOP/expect.err" ]; then
          echo "❌ $label: expected no stderr, got: $(<"$NIX_BUILD_TOP/expect.err")" >&2
          exit 1
        fi
        if [ -n "$warning" ] && ! grep -qF -- "$warning" "$NIX_BUILD_TOP/expect.err"; then
          echo "❌ $label: expected '$warning' on stderr, got: $(<"$NIX_BUILD_TOP/expect.err")" >&2
          exit 1
        fi
        echo "✅ $label"
      }
      expect() {
        local label="$1" want="$2"
        shift 2
        expect_warn "$label" "$want" "" "$@"
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
        expect_warn "envFiles load before arg parsing" "Alice file" \
          "name is reserved, skipped" "$prog"
        expect_warn "arguments keep their parsed value" "Bob file" \
          "name is reserved, skipped" "$prog" --name Bob
        expect_warn "caller env wins over envFiles" "Alice shell" \
          "name is reserved, skipped" env GREET_SOURCE=shell "$prog"
      done
      echo "✅ envFiles load before arg parsing (vanilla + flake-parts)"

      printf 'GREET_NAME=Alice\nGREET_SOURCE=file\nDB=local\n' >.env
      mkdir hostile
      cp .env hostile/.env
      printf 'LETS_ENV_FILES=x\nLETS_NO_ENV_FILES=1\nLETS_ENV_SOURCES=x\n' >>hostile/.env
      printf 'LETS_ENV_VARS=DB=injected\n' >>hostile/.env
      printf 'LETS_SECRETS=bad\n' >>hostile/.env
      printf 'DB=prod\n' >.prod.env
      cp .prod.env hostile/.prod.env
      printf 'BROKEN\n' >.bad.env
      printf 'DB=dev\n' >.dev.env
      printf 'DB=dev-secret\n' >.dev.enc.env
      printf 'DB=prod-secret\n' >.prod.enc.env
      printf 'DB=amp\n' >'.a&b.enc.env'
      printf '_LETS_SECRET_BIN=/nowhere\nLETS_SECRETS_DIR=/nowhere\n' >.hijack.env
      ${composed "vanilla" vanilla.apps.${system}}
      ${composed "flake-parts" fp.apps.${system}}
      echo "✅ env precedence holds across composed tasks (vanilla + flake-parts)"

      mkdir -p e2e/bin e2e/apps e2e/sub
      touch e2e/flake.nix
      printf 'DB=local\n' >e2e/.env
      printf 'DB=cli\n' >e2e/sub/.cli.env
      ln -s ${vanilla.apps.${system}.plain.program} e2e/apps/plain
      ln -s ${vanilla.apps.${system}.parent_cd.program} e2e/apps/parent_cd
      printf 'DB=e2e-secret\n' >e2e/.dev.enc.env
      printf '#!%s\nexec "$LETS_TEST_APPS/''${5#.#}" "''${@:7}"\n' ${pkgs.runtimeShell} \
        >e2e/bin/nix
      chmod +x e2e/bin/nix
      cd e2e/sub
      export LETS_TEST_APPS="$PWD/../apps"
      lets="${vanilla.packages.${system}.lets}/bin/lets"
      PATH="$PWD/../bin:$PATH" expect "lets -E reaches the task" cli \
        "$lets" -E .cli.env plain
      PATH="$PWD/../bin:$PATH" expect_warn "lets -E reaches a child task" cli \
        '.env not found, skipped (from envFiles)' "$lets" -E .cli.env parent_cd
      PATH="$PWD/../bin:$PATH" expect "LETS_ENV_FILES resolves from the caller" cli \
        env LETS_ENV_FILES=.cli.env "$lets" plain
      PATH="$PWD/../bin:$PATH" expect "lets runs tasks from the project root" local \
        "$lets" plain
      PATH="$PWD/../bin:$PATH" expect "lets -S decrypts from the project root" \
        e2e-secret "$lets" -S dev plain
      PATH="$PWD/../bin:$PATH" expect_warn "lets -S survives a child's cd" \
        e2e-secret '.env not found, skipped (from envFiles)' "$lets" -S dev parent_cd
      unset LETS_TEST_APPS
      cd ../..
      echo "✅ the lets wrapper hands CLI files and secrets to tasks"

      expect "loading env files keeps the shell options" clean \
        ${vanilla.apps.${system}.shell_state.program}
      echo "✅ loading env files keeps the shell options"

      expect "an empty caller value wins over envFiles" "" \
        env DB= ${vanilla.apps.${system}.plain.program}
      echo "✅ an empty caller value wins over envFiles"

      cp .env .env.bak
      printf 'TOKEN=f1lesecret\n' >>.env
      err="$(env CALLER_TOKEN=c4llersecret LETS_ENV_VARS=VAR_TOKEN=v4rsecret \
        ${pkgs.bash}/bin/bash -x ${vanilla.apps.${system}.quiet.program} 2>&1)"
      mv .env.bak .env
      if [[ $err == *f1lesecret* || $err == *c4llersecret* || $err == *v4rsecret* ]]; then
        echo "❌ envFiles traced a value under bash -x: $err" >&2
        exit 1
      fi
      if [[ $err != *_lets_env_export* ]]; then
        echo "❌ bash -x did not trace the env loading: $err" >&2
        exit 1
      fi
      echo "✅ loading env files never traces values"

      mkdir layers
      cd layers
      printf 'DB=local\n' >.env
      printf 'DB=other\n' >.local.env
      printf 'DB=prod\n' >.prod.env
      expect "later envFiles entry wins" other ${layeredApps.plain.program}
      expect "a shell value equal to the last envFiles value wins" other \
        env DB=other ${layeredApps.loader.program}
      expect "a shell value equal to an earlier envFiles value wins" local \
        env DB=local ${layeredApps.loader.program}
      cd ..
      echo "✅ envFiles entries load in order"

      mkdir selfdefault
      cd selfdefault
      printf 'DB=''${DB:-local}\n' >.env
      printf 'DB=later\n' >.local.env
      expect "a custom shell value beats a self-default file" shell \
        env DB=shell ${layeredApps.plain.program}
      expect "a shell value equal to a self-default wins" local \
        env DB=local ${layeredApps.plain.program}
      printf 'DB=''${DB:-local}\n' >.local.env
      printf 'DB=prod\n' >.prod.env
      expect "a custom shell value beats two self-default files" shell \
        env DB=shell ${layeredApps.loader.program}
      expect "a shell value equal to two self-defaults wins" local \
        env DB=local ${layeredApps.loader.program}
      cd ..
      echo "✅ the shell beats self-default files"

      mkdir derived
      cd derived
      printf '%s\n' 'DB_HOST=''${DB_HOST:-localhost}' \
        'API_URL="https://$DB_HOST/api"' >.env
      printf 'API_URL=https://task/api\n' >.api.env
      expect "a derived value is a file value when run directly" \
        https://task/api \
        env DB_HOST=custom ${vanilla.apps.${system}.api_task.program}
      expect "a derived value in the shell wins" \
        https://custom/api \
        env DB_HOST=custom API_URL=https://custom/api \
        ${vanilla.apps.${system}.api_task.program}
      cd ..
      echo "✅ derived values follow the shell"

      mkdir cli-required
      cd cli-required
      printf '%s\n' 'DB=''${DB:?set DB first}' >.env
      printf '%s\n' 'OTHER=''${OTHER:?-E needs OTHER}' >.req.env
      expect "-e fills a required value in envFiles" abc \
        env LETS_ENV_VARS=DB=abc ${vanilla.apps.${system}.plain.program}
      expect "-e fills a required value in -E files" "abc two" \
        env LETS_ENV_SOURCES="file:$PWD/.req.env" \
        LETS_ENV_VARS=$'DB=abc\nOTHER=two' ${vanilla.apps.${system}.plain_two.program}
      cd ..
      mkdir cli-derived
      cd cli-derived
      printf '%s\n' 'DB_HOST=prod' >.env
      printf '%s\n' 'API_URL="https://$DB_HOST/api"' >.api.env
      printf '%s\n' 'DB_HOST=cli-file' 'API_URL="https://$DB_HOST/cli"' >.cli.env
      expect "-e feeds values derived in a task's envFiles" https://db.local/api \
        env LETS_ENV_VARS=DB_HOST=db.local ${vanilla.apps.${system}.api_task.program}
      expect "-e feeds values derived in -E files" https://db.local/cli \
        env LETS_ENV_SOURCES="file:$PWD/.cli.env" LETS_ENV_VARS=DB_HOST=db.local \
        ${vanilla.apps.${system}.api_task.program}
      cd ..
      echo "✅ files see -e values while they load"

      mkdir guarded
      cd guarded
      touch .env
      printf 'DB=prod\n' >.prod.env
      expect "LETS_NO_ENV_FILES reaches a child" unset \
        env LETS_NO_ENV_FILES=1 ${vanilla.apps.${system}.parent_prod_or_unset.program}
      printf '%s\n' UID=0 IFS=x RED=x CDPATH=/tmp DB=ok >.rt.env
      expect_warn "runtime and shell names are skipped" ok 'IFS is reserved, skipped' \
        env LETS_ENV_FILES=.rt.env ${vanilla.apps.${system}.plain.program}
      expect_warn "a skipped IFS leaves the shell as it was" clean \
        'IFS is reserved, skipped' \
        env LETS_ENV_FILES=.rt.env ${vanilla.apps.${system}.shell_state.program}
      env LETS_ENV_FILES=.rt.env ${vanilla.apps.${system}.plain.program} \
        2>rt.err >/dev/null
      for name in UID IFS RED CDPATH; do
        has_err rt.err "$name is reserved, skipped"
      done
      printf 'DB=glob\n' >g1.env
      printf 'DB=globbed\n' >.dev.enc.env
      touch dev
      if env LETS_ENV_FILES='g*.env' ${vanilla.apps.${system}.plain.program} \
        2>glob.err; then
        echo "❌ a LETS_ENV_FILES glob should not match a file" >&2
        exit 1
      fi
      has_err glob.err 'g*.env not found (from LETS_ENV_FILES)'
      if env LETS_SECRETS='de?' ${vanilla.apps.${system}.plain.program} \
        2>glob.err; then
        echo "❌ a LETS_SECRETS glob should not match a file" >&2
        exit 1
      fi
      has_err glob.err '.de?.enc.env failed (exit 1) (from LETS_SECRETS)'
      expect "LETS_ENV_VARS values are not expanded" '$(echo x) $HOME' \
        env LETS_ENV_VARS='DB=$(echo x) $HOME' ${vanilla.apps.${system}.plain.program}
      cd ..
      echo "✅ CLI entries are not globbed and -e values stay literal"

      printf 'not dotenv\n' >.rawjunk.enc.env
      printf 'TOKEN=\n' >.rawblank.enc.env
      printf 'PATH=/x\nNOISY_EMPTY=\nNOISY=1\n' >.rawnoisy.enc.env
      printf 'DB=leak\nBROKEN\n' >.rawhalf.enc.env
      printf 'DB=leak\nX==\n' >.rawhalfeq.enc.env
      expect_warn "onError warn: secrets.files failures let the task go on" local \
        'bad.enc.env failed (exit 3), skipped (from secrets.files)' \
        ${warnApps.plain.program}
      ${warnApps.plain.program} 2>warn.err >/dev/null
      has_err warn.err 'bad.enc.env failed (exit 3), skipped (from secrets.files)'
      has_err warn.err 'empty.enc.env printed nothing, skipped (from secrets.files)'
      has_err warn.err \
        ".rawjunk.enc.env:1: expected '=' right after the name, decoder output must be KEY=VALUE lines, skipped (from secrets.files)"
      has_err warn.err \
        '.rawblank.enc.env printed no KEY=VALUE line with a value, skipped (from secrets.files)'
      has_err warn.err '.rawhalf.enc.env:2: expected '"'"'='"'"' after the name'
      has_err warn.err ".rawhalfeq.enc.env: a value is only '='"
      expect "onError ignore: secrets.files failures run silently" local \
        ${ignoreApps.plain.program}
      echo "✅ onError warn and ignore keep the task running"

      for prog in ${warnApps.plain.program} ${ignoreApps.plain.program}; do
        if env LETS_SECRETS=dev:bad "$prog" 2>strict.err; then
          echo "❌ onError should not cover LETS_SECRETS" >&2
          exit 1
        fi
        has_err strict.err 'bad.enc.env failed (exit 3) (from LETS_SECRETS)'
        if env LETS_ENV_SOURCES=secret:bad "$prog" 2>strict.err; then
          echo "❌ onError should not cover -S" >&2
          exit 1
        fi
        has_err strict.err 'bad.enc.env failed (exit 3) (from --secret)'
      done
      for prog in ${warnApps.needs_bad.program} ${ignoreApps.needs_bad.program}; do
        if "$prog" 2>strict.err; then
          echo "❌ onError should not cover a task's secrets" >&2
          exit 1
        fi
        has_err strict.err 'bad.enc.env failed (exit 3) (from secrets)'
      done
      echo "✅ onError only covers secrets.files"

      if ${unreachableWarn.apps.${system}.plain.program} 2>unreachable.err; then
        echo "❌ a decoder missing from PATH should fail even with onError warn" >&2
        exit 1
      fi
      has_err unreachable.err \
        'secrets: dev: decoder command not found or not executable (exit 127) (from secrets.files)'
      echo "✅ a decoder missing from PATH fails even with onError warn"

      if ${(strict [ "bad" ]).plain.program} 2>strict.err; then
        echo "❌ a failing secrets.files decoder should fail by default" >&2
        exit 1
      fi
      has_err strict.err 'bad.enc.env failed (exit 3) (from secrets.files)'
      if ${(strict [ "empty" ]).plain.program} 2>strict.err; then
        echo "❌ an empty secrets.files output should fail by default" >&2
        exit 1
      fi
      has_err strict.err 'empty.enc.env printed nothing (from secrets.files)'
      if ${(strict [ "rawjunk" ]).plain.program} 2>strict.err; then
        echo "❌ unparsable secrets.files output should fail by default" >&2
        exit 1
      fi
      has_err strict.err ".rawjunk.enc.env:1: expected '=' right after the name"
      if ${(strict [ "rawblank" ]).plain.program} 2>strict.err; then
        echo "❌ secrets.files output without a value should fail by default" >&2
        exit 1
      fi
      has_err strict.err '.rawblank.enc.env printed no KEY=VALUE line with a value'
      echo "✅ onError defaults to fail for secrets.files"

      if ${noexecApps.needs_dev.program} 2>noexec.err; then
        echo "❌ a decoder command that cannot run should fail" >&2
        exit 1
      fi
      has_err noexec.err \
        '.dev.enc.env: decoder command not found or not executable (exit 126) (from secrets)'
      echo "✅ a decoder command that cannot run fails the task"

      if env LETS_SECRETS=dev ${expand} 2>nodecoder.err >/dev/null; then
        echo "❌ LETS_SECRETS without secrets.command should fail" >&2
        exit 1
      fi
      has_err nodecoder.err \
        'no decoder configured (secrets.command) (from LETS_SECRETS)'
      if env LETS_ENV_SOURCES=secret:dev ${expand} 2>nodecoder.err >/dev/null; then
        echo "❌ -S without secrets.command should fail" >&2
        exit 1
      fi
      has_err nodecoder.err 'no decoder configured (secrets.command) (from --secret)'
      top="$PWD"
      mkdir -p realise/proj/sub
      touch realise/proj/flake.nix
      printf '#!%s\nprintf "%%s " "$@" >%s/realise/args\nexit 1\n' ${pkgs.runtimeShell} "$top" \
        >realise/nix-store
      printf '#!%s\nprintf "%%s %%s" "$PWD" "$*" >%s/realise/eval\n' ${pkgs.runtimeShell} "$top" \
        >realise/nix
      chmod +x realise/nix-store realise/nix
      unbuilt_fails() {
        local label="$1" dir="$2" app="$3"
        rm -f "$top/realise/args" "$top/realise/eval"
        if (cd "$dir" && env PATH="$top/realise:$PATH" LETS_SECRETS=dev "$app") \
          2>"$top/unbuilt.err"; then
          echo "❌ $label: a decoder that cannot be built should fail" >&2
          exit 1
        fi
        has_err "$top/unbuilt.err" 'secrets: cannot build the decoder (from LETS_SECRETS); run the task with nix run --no-eval-cache, through lets or in the dev shell'
        case "$(<"$top/realise/args")" in
        "--realise --no-gc-warning /nix/store/"*.drv" ") ;;
        *)
          echo "❌ $label: the decoder should be realised, got: $(<"$top/realise/args")" >&2
          exit 1
          ;;
        esac
      }
      sed "s|^_LETS_SECRET_DRV=.*|_LETS_SECRET_DRV=$storedDrv|" \
        ${unbuilt.apps.${system}.plain.program} >realise/stored
      chmod +x realise/stored
      unbuilt_fails "derivation in the store" realise/proj/sub "$top/realise/stored"
      if [ "$(<realise/args)" != "--realise --no-gc-warning $storedDrv " ]; then
        echo "❌ the decoder derivation in the store should be realised, got: $(<realise/args)" >&2
        exit 1
      fi
      if [ -e realise/eval ]; then
        echo "❌ a decoder derivation in the store needs no evaluation, got: $(<realise/eval)" >&2
        exit 1
      fi
      echo "✅ a missing decoder fails the task, an unbuilt one is built on demand"

      unbuilt_fails "derivation gone" realise/proj/sub \
        ${unbuilt.apps.${system}.plain.program}
      has_err "$top/unbuilt.err" "secrets: re-evaluating $top/realise/proj to rebuild the decoder"
      if [ "$(<realise/eval)" != "$top/realise/proj path-info --derivation --no-eval-cache .#plain" ]; then
        echo "❌ a gone decoder derivation should re-evaluate the nearest flake, got: $(<realise/eval)" >&2
        exit 1
      fi
      echo "✅ a gone decoder derivation re-evaluates the nearest flake before building"

      unbuilt_fails "no flake" . ${unbuilt.apps.${system}.plain.program}
      if [ -e realise/eval ]; then
        echo "❌ without a flake.nix nothing should be evaluated, got: $(<realise/eval)" >&2
        exit 1
      fi
      echo "✅ without a flake.nix a gone decoder derivation fails with the fix"

      sed -e "s|^_LETS_SECRET_BIN=.*|_LETS_SECRET_BIN=/nowhere/lets-decoder|" \
        -e "s|^_LETS_SECRET_DRV=.*|_LETS_SECRET_DRV=|" \
        ${unbuilt.apps.${system}.plain.program} >realise/nodrv
      chmod +x realise/nodrv
      rm -f realise/args
      if env PATH="$top/realise:$PATH" LETS_SECRETS=dev realise/nodrv 2>nodrv.err; then
        echo "❌ a decoder without a derivation should fail" >&2
        exit 1
      fi
      has_err nodrv.err 'secrets: cannot build the decoder (from LETS_SECRETS)'
      if [ -e realise/args ]; then
        echo "❌ an empty derivation path should not reach nix-store, got: $(<realise/args)" >&2
        exit 1
      fi
      echo "✅ a decoder without a derivation fails without calling nix-store"

      if grep -q lets-decoder ${
        pkgs.closureInfo { rootPaths = [ unbuilt.packages.${system}.plain ]; }
      }/store-paths; then
        echo "❌ a task that never decrypts should keep the decoder out of its closure" >&2
        exit 1
      fi
      echo "✅ a task that never decrypts keeps the decoder out of its closure"

      mkdir -p rel/sub
      touch rel/flake.nix
      printf 'DB=root\n' >rel/.env
      printf 'DB=sub\n' >rel/sub/.env
      got="$(cd rel/sub && ${vanilla.apps.${system}.plain.program} 2>"$top/rel.err")"
      if [ "$got" != sub ] || [ -s rel.err ]; then
        echo "❌ envFiles should load from the directory the task runs in, got: $got $(<rel.err)" >&2
        exit 1
      fi
      echo "✅ envFiles load from the directory the task runs in"

      mkdir nul
      printf 'DB=a\0b\n' >nul/.env
      if env -C nul ${vanilla.apps.${system}.plain.program} 2>nul.err; then
        echo "❌ an env file with a NUL byte should fail the task" >&2
        exit 1
      fi
      has_err nul.err 'env: .env contains NUL bytes (from envFiles)'
      echo "✅ an env file with a NUL byte fails the task"

      mkdir trail
      printf 'DB=x\\\n' >trail/.env
      printf 'DB=y\\\n' >trail/.rawtrail.enc.env
      expect "a backslash before the last newline of a file is a line continuation" x \
        env -C trail ${vanilla.apps.${system}.plain.program}
      expect "a backslash before the last newline of decoder output is a line continuation" y \
        env -C trail LETS_SECRETS=rawtrail ${vanilla.apps.${system}.plain.program}

      printf 'BASE=1\nDB=base-secret\n' >.base.enc.env
      expect "secrets.files load in every task, after envFiles" "base-secret 1" \
        ${withFilesApps.plain_base.program}
      expect "flake-parts: secrets.files load in every task" "base-secret 1" \
        ${fpFilesApps.plain_base.program}
      expect "shell value equal to secrets.files wins" base-secret \
        env DB=base-secret ${withFilesApps.loader.program}
      expect "a task's envFiles beat secrets.files" prod ${withFilesApps.loader.program}
      expect "a task's secrets beat secrets.files" dev-secret ${withFilesApps.needs_dev.program}
      expect "flake-parts: a task's envFiles beat secrets.files" prod \
        ${fpFilesApps.loader.program}
      expect "flake-parts: a task's secrets beat secrets.files" dev-secret \
        ${fpFilesApps.needs_dev.program}
      expect_warn "flake-parts: onError warn lets the task go on" local \
        'skipped (from secrets.files)' ${fpWarnApps.plain.program}
      expect "secrets.files lose to the shell" "shell 1" \
        env DB=shell ${withFilesApps.plain_base.program}
      expect "LETS_NO_ENV_FILES skips secrets.files" "unset unset" \
        env LETS_NO_ENV_FILES=1 ${withFilesApps.plain_base.program}
      expect_warn "LETS_NO_ENV_FILES=0 still loads envFiles" local \
        'LETS_NO_ENV_FILES must be 1 to skip env files, ignored' \
        env LETS_NO_ENV_FILES=0 ${vanilla.apps.${system}.plain.program}
      expect_warn "LETS_NO_ENV_FILES=false still loads secrets.files" "base-secret 1" \
        'LETS_NO_ENV_FILES must be 1 to skip env files, ignored' \
        env LETS_NO_ENV_FILES=false ${withFilesApps.plain_base.program}
      env LETS_NO_ENV_FILES=0 ${withFilesApps.loader.program} 2>nofiles.err >/dev/null
      if [ "$(grep -c 'LETS_NO_ENV_FILES must be 1' nofiles.err)" != 1 ]; then
        echo "❌ LETS_NO_ENV_FILES should warn once per task, got: $(<nofiles.err)" >&2
        exit 1
      fi
      echo "✅ LETS_NO_ENV_FILES warns once per task"
      expect "an empty -e value beats a file value" "" \
        env LETS_ENV_VARS=DB= ${vanilla.apps.${system}.plain.program}
      help_out="$(${vanilla.apps.${system}.help.program})"
      for flag in "-E, --env-file" "-e, --env " "-S, --secret" "--no-env-files"; do
        case "$help_out" in
        *"lets $flag"*) ;;
        *)
          echo "❌ help should list lets $flag" >&2
          exit 1
          ;;
        esac
      done
      echo "✅ help lists the env flags"
      expect "a parent's secrets.files values win in a child" base-secret \
        ${withFilesApps.parent_loader.program}
      mkdir chain
      cd chain
      printf 'CONF_DIR=confdir\n' >.conf.env
      mkdir confdir
      printf 'DB=nested\n' >confdir/x.env
      expect "an envFiles entry expands a value from an earlier file" nested \
        ${chained.apps.${system}.plain.program}
      expect "-E expands a value from envFiles" nested \
        env LETS_ENV_SOURCES='file:$CONF_DIR/x.env' \
        ${confOnly.apps.${system}.plain.program}
      mkdir otherdir
      printf 'DB=other\n' >otherdir/x.env
      expect "an envFiles entry expands a value from -e" other \
        env LETS_ENV_VARS=CONF_DIR=otherdir ${chained.apps.${system}.plain.program}
      expect "-E expands a value from -e" other \
        env LETS_ENV_SOURCES='file:$CONF_DIR/x.env' LETS_ENV_VARS=CONF_DIR=otherdir \
        ${confOnly.apps.${system}.plain.program}
      cd ..
      echo "✅ entries expand values from earlier files and -e"

      cp .env .env.seen
      printf 'FROM_ENV=hello\n' >>.env
      expect "a task's secrets see envFiles values" hello \
        ${vanilla.apps.${system}.seen_dev.program}
      expect "LETS_SECRETS sees envFiles values" hello \
        env LETS_SECRETS=dev ${vanilla.apps.${system}.plain_seen.program}
      expect "secrets.files see envFiles values" hello \
        ${withFilesApps.plain_seen.program}
      expect "a task's secrets see -e values" cli \
        env LETS_ENV_VARS=FROM_ENV=cli ${vanilla.apps.${system}.seen_dev.program}
      expect "LETS_SECRETS sees -e values" cli \
        env LETS_SECRETS=dev LETS_ENV_VARS=FROM_ENV=cli \
        ${vanilla.apps.${system}.plain_seen.program}
      expect "secrets.files see -e values" cli \
        env LETS_ENV_VARS=FROM_ENV=cli ${withFilesApps.plain_seen.program}
      mv .env.seen .env
      echo "✅ the decoder sees values from earlier files and -e"

      expect "{} keeps its position in the decoder command" \
        "[--first][.dev.enc.env][--last]" \
        ${posApps.plain_argv.program}

      has_err ${vanilla.apps.${system}.plain.program} "lets-decoder"
      if grep -q "^export PATH=.*lets-decoder" \
        ${vanilla.apps.${system}.plain.program}; then
        echo "❌ plain has the decoder on its PATH" >&2
        exit 1
      fi
      grep -q "^export PATH=.*lets-decoder" ${vanilla.apps.${system}.needs_dev.program} || {
        echo "❌ needs_dev lacks the decoder on its PATH" >&2
        exit 1
      }
      echo "✅ only decrypting tasks carry the decoder"

      expect "a command list keeps its words in place, spaces included" \
        "[--first][.dev.enc.env][--last][a b]" \
        ${listApps.plain_argv.program}
      if ${unreachableApps.needs_dev.program} 2>unreachable.err; then
        echo "❌ a decoder command missing from PATH should fail" >&2
        exit 1
      fi
      has_err unreachable.err \
        'secrets: dev: decoder command not found or not executable (exit 127) (from secrets)'
      echo "✅ a decoder command missing from PATH fails the task"

      printf 'api_key: c2VjcmV0X3Rva2Vu==\n' >.leak.enc.env
      if env LETS_SECRETS=leak ${vanilla.apps.${system}.plain.program} \
        2>leak.err; then
        echo "❌ decoder output that is not dotenv should fail" >&2
        exit 1
      fi
      has_err leak.err \
        'secrets: .leak.enc.env:3: invalid variable name, decoder output must be KEY=VALUE lines (from LETS_SECRETS)'
      if grep -q 'c2VjcmV0' leak.err; then
        echo "❌ a malformed secret line was printed: $(<leak.err)" >&2
        exit 1
      fi
      printf 'TOKEN"s3cr3t\n' >.rawleak1.enc.env
      printf 'TOKEN="s3cr3t\n' >.rawleak2.enc.env
      printf 'TOKEN="s3cr3t" x\n' >.rawleak3.enc.env
      for name in rawleak1 rawleak2 rawleak3; do
        if env LETS_SECRETS=$name ${vanilla.apps.${system}.plain.program} \
          2>leak.err; then
          echo "❌ malformed decoder output should fail ($name)" >&2
          exit 1
        fi
        if grep -q s3cr3t leak.err; then
          echo "❌ a malformed secret line was printed ($name): $(<leak.err)" >&2
          exit 1
        fi
      done
      printf 'PATH=/nowhere\nDB=res\n' >.rawres.enc.env
      expect_warn "a reserved key in decoder output is skipped" res \
        'PATH is reserved, skipped' \
        env LETS_SECRETS=rawres ${vanilla.apps.${system}.plain.program}
      env LETS_SECRETS=rawres ${vanilla.apps.${system}.plain.program} \
        2>res.err >/dev/null
      has_err res.err 'secrets: .rawres.enc.env:1: PATH is reserved, skipped (from LETS_SECRETS)'
      echo "✅ malformed decoder output fails without being printed"

      err="$(${pkgs.bash}/bin/bash -x ${vanilla.apps.${system}.quiet_dev.program} 2>&1)"
      if [[ $err == *dev-secret* || $err != *_lets_env_export* ]]; then
        echo "❌ a task's secrets were traced, or nothing was, under bash -x: $err" >&2
        exit 1
      fi
      err="$(env LETS_SECRETS=prod ${pkgs.bash}/bin/bash -x \
        ${vanilla.apps.${system}.quiet.program} 2>&1)"
      if [[ $err == *prod-secret* || $err != *_lets_env_export* ]]; then
        echo "❌ LETS_SECRETS were traced, or nothing was, under bash -x: $err" >&2
        exit 1
      fi
      echo "✅ decrypted secrets are never traced"

      cp .env .env.bak
      printf 'TOKEN=f1lesecret\n' >>.env
      printf 'CLI_TOKEN=cl1secret\n' >.xtrace.env
      err="$(env SHELLOPTS=xtrace LETS_ENV_SOURCES="file:$PWD/.xtrace.env" \
        LETS_ENV_VARS=VAR_TOKEN=v4rsecret \
        ${vanilla.apps.${system}.quiet_dev.program} 2>&1)"
      mv .env.bak .env
      for value in f1lesecret dev-secret cl1secret v4rsecret; do
        if [[ $err == *"$value"* ]]; then
          echo "❌ $value was traced under SHELLOPTS=xtrace: $err" >&2
          exit 1
        fi
      done
      if [[ $err != *_lets_env_export* ]]; then
        echo "❌ SHELLOPTS=xtrace did not trace the task: $err" >&2
        exit 1
      fi
      echo "✅ files, secrets, -E and -e are never traced under xtrace"
      ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        big="$(head -c 100000 /dev/zero | tr '\0' a)"
        printf 'DB=%s\n' "$big$big" >.big.enc.env
        env LETS_SECRETS=big LETS_ENV_VARS="OTHER=$big" \
          ${pkgs.strace}/bin/strace -f -qq -e trace=%file -o big.trace \
          ${vanilla.apps.${system}.plain_two.program} >big.out
        if [ "$(wc -c <big.out)" != 300002 ]; then
          echo "❌ a large secret and -e value did not load: $(wc -c <big.out) bytes" >&2
          exit 1
        fi
        if grep -F O_CREAT big.trace; then
          echo "❌ loading a large secret and -e value created a file" >&2
          exit 1
        fi
        echo "✅ large secrets and -e values are never written to disk"
      ''}

      expect "loading leaves no decoder text in the task" clean \
        ${vanilla.apps.${system}.residue_dev.program}

      grep -q lets-decoder ${
        pkgs.closureInfo { rootPaths = [ vanilla.packages.${system}.lets ]; }
      }/store-paths
      has_err ${fp.packages.${system}.lets}/bin/lets "SECRETS_PATTERN='.{name}.enc.env'"
      has_err ${vanilla.packages.${system}.lets}/bin/lets "SECRETS_PATTERN='.{name}.enc.env'"
      echo "✅ lets carries the decoder and the secrets pattern"

      printf 'c2VjcmV0dG9rZW4=\n' >.raw.enc.env
      printf '# nothing\n' >.rawcomment.enc.env
      for name in raw rawcomment; do
        if env LETS_SECRETS=$name ${vanilla.apps.${system}.plain.program} \
          2>raw.err; then
          echo "❌ decoder output without KEY=VALUE should fail ($name)" >&2
          exit 1
        fi
        has_err raw.err \
          "secrets: .$name.enc.env printed no KEY=VALUE line with a value"
      done
      echo "✅ decoder output without a KEY=VALUE line fails the task"

      printf 'PATH=/x\n' >.rawonlyres.enc.env
      if env LETS_SECRETS=rawonlyres ${vanilla.apps.${system}.plain.program} \
        2>onlyres.err; then
        echo "❌ decoder output with only reserved keys should fail" >&2
        exit 1
      fi
      has_err onlyres.err 'PATH is reserved, skipped'
      has_err onlyres.err 'printed no KEY=VALUE line with a value'
      echo "✅ decoder output with only reserved keys says why it fails"

      printf '%s\n' 'A=''${MISSING_X:?need it}' >.rawreq.enc.env
      if env LETS_SECRETS=rawreq ${vanilla.apps.${system}.plain.program} \
        2>req.err; then
        echo "❌ a required value missing from decoder output should fail" >&2
        exit 1
      fi
      has_err req.err '.rawreq.enc.env:1: need it (from LETS_SECRETS)'
      echo "✅ a required value in decoder output fails without the format hint"

      printf 'DB=app\nDB_PASSWORD=\n' >.rawpartial.enc.env
      expect_warn "an empty secret value warns with its key" app \
        'secrets: .rawpartial.enc.env: DB_PASSWORD is empty (from LETS_SECRETS)' \
        env LETS_SECRETS=rawpartial ${vanilla.apps.${system}.plain.program}

      printf 'c2VjcmV0dG9rZQ==\n' >.rawpad.enc.env
      if env LETS_SECRETS=rawpad ${vanilla.apps.${system}.plain.program} \
        2>rawpad.err; then
        echo "❌ a bare padded value from the decoder should fail" >&2
        exit 1
      fi
      has_err rawpad.err \
        "secrets: .rawpad.enc.env: a value is only '=', decoder output must be KEY=VALUE lines (from LETS_SECRETS)"
      if grep -q c2VjcmV0 rawpad.err; then
        echo "❌ a bare secret was printed: $(<rawpad.err)" >&2
        exit 1
      fi
      echo "✅ decoder output with a value that is only = fails the task"
      printf "DB='=Xy9q'\n" >.eqquoted.enc.env
      printf 'DB==abc\n' >.equnquoted.enc.env
      expect "a quoted secret value may start with =" "=Xy9q" \
        env LETS_SECRETS=eqquoted ${vanilla.apps.${system}.plain.program}
      expect "an unquoted secret value may start with =" "=abc" \
        env LETS_SECRETS=equnquoted ${vanilla.apps.${system}.plain.program}

      printf 'TOKEN s3cr3t==\n' >.typo.env
      if env LETS_ENV_FILES=.typo.env ${vanilla.apps.${system}.plain.program} \
        2>typo.err; then
        echo "❌ a line with an invalid name should fail" >&2
        exit 1
      fi
      has_err typo.err "typo.env:1: expected '=' right after the name (from LETS_ENV_FILES)"
      if grep -q s3cr3t typo.err; then
        echo "❌ an invalid line was printed: $(<typo.err)" >&2
        exit 1
      fi
      echo "✅ an invalid name fails without printing the line"

      if env LETS_SECRETS=empty ${vanilla.apps.${system}.plain.program} \
        2>empty.err; then
        echo "❌ a decoder that prints nothing should fail the task" >&2
        exit 1
      fi
      has_err empty.err 'secrets: .empty.enc.env printed nothing (from LETS_SECRETS)'
      echo "✅ a decoder that prints nothing fails the task"

      mkdir home dir
      printf 'FROM_HOME=1\n' >home/home.env
      printf 'FROM_TILDE=1\n' >home/tilde.env
      printf 'FROM_BRACED=1\n' >dir/braced.env
      printf 'FROM_PLAIN=1\n' >dir/plain.env
      expect_warn "envFiles entries expand ~/ and variables" "1 1 1 1" \
        'pwned`.env not found, skipped' \
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
          *".env:1: expected '=' after the name (from envFiles)"*) ;;
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
      *".env:1: expected '=' after the name (from envFiles)"*) ;;
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
      help="$(${vanilla.apps.${system}.needs_dev.program} --help)" || {
        echo "❌ --help should not decrypt a task's secrets" >&2
        exit 1
      }
      cd ..
      echo "✅ --help prints usage without loading envFiles or secrets"

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
