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
}
