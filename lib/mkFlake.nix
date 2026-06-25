{
  nixpkgs,
  systems,
  tasks,
  specialArgs ? { },
  version ? "0.0.0",
  overlays ? [ ],
  devShell ? { },
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
      taskSet = import ./loadTasks.nix {
        inherit pkgs system specialArgs;
        src = tasks;
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
      inherit pkgs out letsCmd;
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
    default = p.pkgs.mkShell (
      {
        packages = [ p.letsCmd ] ++ (devShell.packages or [ ]);
        shellHook = ''
          ${devShell.shellHook or ""}
          __lets_bash_version="''${BASH_VERSION:-}"
          if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
            # shellcheck disable=SC1091
            source ${p.out.completionScripts.bash}
          fi
        '';
      }
      // removeAttrs devShell [
        "packages"
        "shellHook"
      ]
    );
  }) built;
}
