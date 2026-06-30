{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
      flake-parts,
    }:
    let
      version = "0.1.0";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

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

      perSystem =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tasks = mkBaseTasks { inherit pkgs; };
          taskOutputs = mkOutputs { inherit pkgs tasks; };
          letsCmd = mkLets { inherit pkgs tasks version; };
          preCommitCheck = pre-commit-hooks.lib.${system}.run {
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
        in
        {
          inherit
            pkgs
            taskOutputs
            letsCmd
            preCommitCheck
            ;
        };

      built = forAllSystems perSystem;
    in
    {
      devShells = forAllSystems (
        system:
        let
          inherit (built.${system})
            pkgs
            taskOutputs
            letsCmd
            preCommitCheck
            ;
        in
        {
          default = pkgs.mkShell {
            packages = [ letsCmd ];
            shellHook = ''
              ${preCommitCheck.shellHook}
              __lets_bash_version="''${BASH_VERSION:-}"
              if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
                # shellcheck disable=SC1091
                source ${taskOutputs.completionScripts.bash}
              fi
            '';
            buildInputs = preCommitCheck.enabledPackages;
          };
        }
      );

      apps = forAllSystems (system: built.${system}.taskOutputs.apps);

      packages = forAllSystems (
        system:
        let
          inherit (built.${system}) pkgs letsCmd;
        in
        {
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
        }
      );

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

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      checks = forAllSystems (
        system:
        let
          inherit (built.${system}) pkgs taskOutputs preCommitCheck;
        in
        {
          pre-commit-check = preCommitCheck;
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
        }
      );
    };
}
