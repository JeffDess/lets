version:
{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      cfg = config.lets;
      baseTasks = import ./mkBaseTasks.nix { inherit pkgs; };
      taskSet = import ./loadTasks.nix {
        inherit pkgs system;
        src = cfg.tasks;
        specialArgs = {
          inherit baseTasks;
        }
        // cfg.specialArgs;
      };
      out = import ./mkOutputs.nix {
        inherit pkgs;
        tasks = taskSet;
      };
      letsCmd = import ./mkLets.nix {
        inherit pkgs version;
        tasks = taskSet;
      };
    in
    {
      options.lets = {
        tasks = lib.mkOption {
          type = lib.types.unspecified;
          default = null;
          description = "Tasks to wire in: an attrset, a function of the task scope, a path to a file, or a path to a directory.";
        };
        specialArgs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Extra arguments merged into every task's scope (e.g. flake inputs, a second nixpkgs).";
        };
        devShell = lib.mkOption {
          type = lib.types.package;
          description = "Dev shell carrying the `lets` command and its shell completions. Compose it into your own shell with `inputsFrom = [ config.lets.devShell ];`.";
        };
      };

      config = lib.mkIf (cfg.tasks != null) {
        inherit (out) apps;
        packages = {
          lets = letsCmd;
        }
        // out.packages;

        lets.devShell = pkgs.mkShell {
          packages = [ letsCmd ];
          shellHook = ''
            __lets_bash_version="''${BASH_VERSION:-}"
            if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
              # shellcheck disable=SC1091
              source ${out.completionScripts.bash}
            fi
          '';
        };

        devShells.default = lib.mkDefault config.lets.devShell;
      };
    }
  );
}
