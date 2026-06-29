{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
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
      version = "0.1.0";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;
      letsLib = import ./lib;
      inherit (letsLib)
        mkTask
        mkTasks
        loadTasks
        mkOutputs
        mkLets
        mkBaseTasks
        mkFlake
        ;
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

      flakeModules.default = letsLib.flakeModule version;

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
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
      }
      // import ./checks {
        inherit
          pkgs
          system
          self
          nixpkgs
          flake-parts
          taskOutputs
          ;
      };
    };
}
