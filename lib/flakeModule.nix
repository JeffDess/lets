version:
{ flake-parts-lib, lib, ... }:
let
  defaults = import ./secretsDefaults.nix;
in
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
      decoder = import ./secrets.nix { inherit pkgs; } cfg.secrets;
      baseTasks = import ./mkBaseTasks.nix {
        inherit pkgs;
        inherit (cfg) envFiles secrets;
      };
      taskSet = import ./loadTasks.nix {
        inherit pkgs system;
        inherit (cfg) envFiles secrets;
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
        inherit (cfg) secrets;
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
        envFiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Env files loaded before every task, in the POSIX dialect; see the README's Environment files section.";
        };
        secrets = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                command = lib.mkOption {
                  type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
                  description = "Decoder command, with `{}` as a word of its own where the argument goes.";
                };
                runtimeInputs = lib.mkOption {
                  type = lib.types.either (lib.types.listOf lib.types.package) (
                    lib.types.functionTo (lib.types.listOf lib.types.package)
                  );
                  default = defaults.runtimeInputs;
                  description = "Packages the decoder needs, as a list or a function of pkgs.";
                };
                pattern = lib.mkOption {
                  type = lib.types.str;
                  default = defaults.pattern;
                  description = "Turns a secret's name into the decoder's argument; contains `{name}` once.";
                };
                files = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = defaults.files;
                  description = "Secrets decrypted at the start of every task, right after the project's envFiles. Names go through `pattern`, and `--no-env-files` skips them.";
                };
                onError = lib.mkOption {
                  type = lib.types.enum [
                    "fail"
                    "warn"
                    "ignore"
                  ];
                  default = defaults.onError;
                  description = "What a failing decoder does for `secrets.files`: `fail` stops the task, `warn` and `ignore` run without them.";
                };
              };
            }
          );
          default = null;
          description = "Project-wide decoder for encrypted env files.";
        };
        devShell = lib.mkOption {
          type = lib.types.package;
          description = "Dev shell carrying the `lets` command and its shell completions. Compose it into your own shell with `inputsFrom = [ config.lets.devShell ];`.";
        };
      };

      config = lib.mkIf (cfg.tasks != null) {
        inherit (out) apps;
        packages = {
          default = lib.mkDefault letsCmd;
          lets = letsCmd;
        }
        // out.packages;

        lets.devShell = pkgs.mkShell {
          packages = [ letsCmd ] ++ lib.optional (decoder != null) decoder.package;
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
