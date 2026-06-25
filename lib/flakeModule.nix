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
      taskSet = import ./loadTasks.nix {
        inherit pkgs system;
        src = cfg.tasks;
        inherit (cfg) specialArgs;
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
      };

      config = lib.mkIf (cfg.tasks != null) {
        inherit (out) apps;
        packages = {
          lets = letsCmd;
        }
        // out.packages;
        devShells.default = pkgs.mkShell { packages = [ letsCmd ]; };
      };
    }
  );
}
