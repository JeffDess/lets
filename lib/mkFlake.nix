{
  nixpkgs,
  systems,
  tasks,
  specialArgs ? { },
  version ? "0.0.0",
  overlays ? [ ],
}:
let
  eachSystem =
    f:
    builtins.listToAttrs (
      map (system: {
        name = system;
        value = f system;
      }) systems
    );

  perSystem =
    system:
    let
      pkgs = import nixpkgs { inherit system overlays; };
      baseTasks = import ./mkBaseTasks.nix { inherit pkgs; };
      taskSet = import ./loadTasks.nix {
        inherit pkgs system;
        src = tasks;
        specialArgs = {
          inherit baseTasks;
        }
        // specialArgs;
      };
      out = import ./mkOutputs.nix {
        inherit pkgs;
        tasks = taskSet;
      };
      letsCmd = import ./mkLets.nix {
        inherit pkgs version;
        tasks = taskSet;
      };
      letsShell = pkgs.mkShell {
        packages = [ letsCmd ];
        shellHook = ''
          __lets_bash_version="''${BASH_VERSION:-}"
          if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
            # shellcheck disable=SC1091
            source ${out.completionScripts.bash}
          fi
        '';
      };
    in
    {
      inherit
        out
        letsCmd
        letsShell
        ;
    };

  built = eachSystem perSystem;
in
{
  apps = builtins.mapAttrs (_system: p: p.out.apps) built;

  packages = builtins.mapAttrs (
    _system: p:
    {
      default = p.letsCmd;
      lets = p.letsCmd;
    }
    // p.out.packages
  ) built;

  devShells = builtins.mapAttrs (_system: p: {
    default = p.letsShell;
    lets = p.letsShell;
  }) built;
}
