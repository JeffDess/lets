{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      version = "0.2.1";
      letsLib = import ./lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ flake-parts.flakeModules.partitions ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
      };

      partitions.dev = {
        extraInputsFlake = ./dev;
        module = ./dev/flake-module.nix;
      };

      perSystem =
        { pkgs, ... }:
        let
          tasks = letsLib.mkBaseTasks { inherit pkgs; };
          taskOutputs = letsLib.mkOutputs { inherit pkgs tasks; };
          letsCmd = letsLib.mkLets { inherit pkgs tasks version; };
        in
        {
          _module.args = { inherit tasks taskOutputs; };

          inherit (taskOutputs) apps;

          packages = {
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

          formatter = pkgs.nixfmt-tree;
        };

      flake = {
        lib = {
          inherit (letsLib)
            mkTask
            mkTasks
            mkOutputs
            loadTasks
            mkBaseTasks
            ;
          mkLets = args: letsLib.mkLets (args // { inherit version; });
          mkFlake = args: letsLib.mkFlake (args // { inherit version; });
        };

        flakeModules.default = letsLib.flakeModule version;
      };
    };
}
