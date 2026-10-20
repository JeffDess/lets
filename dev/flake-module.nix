{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      system,
      tasks,
      taskOutputs,
      ...
    }:
    {
      pre-commit.settings = {
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

      devShells.default = pkgs.mkShell {
        packages = [ config.packages.lets ];
        shellHook = ''
          ${config.pre-commit.shellHook}
          __lets_bash_version="''${BASH_VERSION:-}"
          if [ -n "$__lets_bash_version" ] && type complete >/dev/null 2>&1; then
            # shellcheck disable=SC1091
            source ${taskOutputs.completionScripts.bash}
          fi
        '';
        buildInputs = config.pre-commit.settings.enabledPackages;
      };

      checks = import ../checks {
        inherit pkgs system taskOutputs;
        inherit (inputs) self nixpkgs flake-parts;
      };
    };
}
