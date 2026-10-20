{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, git-hooks, ... }:
    let
      version = "0.2.1";
      letsLib = import ./lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          tasks = letsLib.mkBaseTasks { inherit pkgs; };
          taskOutputs = letsLib.mkOutputs { inherit pkgs tasks; };
          letsCmd = letsLib.mkLets { inherit pkgs tasks version; };
          preCommitCheck = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              convco = {
                enable = true;
                entry = "${pkgs.lib.getExe tasks.lint_commits.app} --allow-fixup --message-file";
              };
              convco-push = {
                enable = true;
                name = "convco (push)";
                stages = [ "pre-push" ];
                pass_filenames = false;
                always_run = true;
                entry = "${pkgs.lib.getExe tasks.lint_commits.app} --protect main";
              };
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
          devShells.default = pkgs.mkShell {
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

          checks = {
            pre-commit-check = preCommitCheck;
          }
          // import ./checks {
            inherit pkgs system taskOutputs;
            inherit (inputs) self nixpkgs flake-parts;
          };
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
