{
  pkgs,
  tasks ? import ./loadTasks.nix {
    inherit pkgs;
    src = ../tasks;
  },
}:
let
  inherit (import ./render.nix { inherit pkgs; } { inherit tasks; })
    helpLines
    taskHelp
    showDispatch
    ;

  completionScripts = {
    bash = ../completions/lets.bash;
    zsh = ../completions/lets.zsh;
    fish = ../completions/lets.fish;
    nushell = ../completions/lets.nu;
  };

  mkApp = _name: task: {
    type = "app";
    program = pkgs.lib.getExe task.app;
    meta = { inherit (task) description; };
  };
in
{
  packages = builtins.mapAttrs (_name: task: task.app) tasks;

  apps = (builtins.mapAttrs mkApp tasks) // {
    help = {
      type = "app";
      program = "${
        pkgs.writeShellApplication {
          name = "help";
          text = ''
            task="$*"
            if [ -n "$task" ]; then
              ${taskHelp}
              exit 0
            fi

            printf "\n\033[1;36m lets - A Nix Task Runner\033[0m\n"
            printf "\033[2m-------------------------\033[0m\n\n"
            printf "\033[1;4;34mUsage\033[0m\n"
            echo "  lets <task> [args...]"
            echo "  lets -h, --help          Display this help message"
            printf '      \033[32m[task]\033[0m               Show help for a single task\n'
            echo "  lets -s, --show          Show a task's usage, packages and script"
            printf '      \033[32m<task>\033[0m               The task to show\n'
            echo "  lets -c, --completions   Print a shell completion script"
            printf '      \033[32m<shell>\033[0m              bash, zsh, fish or nushell\n'
            echo "  lets -v, --version       Show version, description and repository"
            printf "\n\033[1;4;34mAvailable Tasks\033[0m\n"
            ${helpLines}
            echo
          '';
        }
      }/bin/help";
      meta = {
        description = "List available tasks";
      };
    };

    show = {
      type = "app";
      program = "${
        pkgs.writeShellApplication {
          name = "show";
          runtimeInputs = [ pkgs.bat ];
          text = ''
            if [ "$#" -lt 1 ]; then
              echo "Usage: lets -s, --show <task>" >&2
              exit 1
            fi

            # shellcheck disable=SC2034
            task="$*"
            ${showDispatch}
          '';
        }
      }/bin/show";
      meta = {
        description = "Show a task's usage, packages and script";
      };
    };

    completions = {
      type = "app";
      program = "${
        pkgs.writeShellApplication {
          name = "completions";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            shell="''${1:-}"
            case "$shell" in
            bash) cat ${completionScripts.bash} ;;
            zsh) cat ${completionScripts.zsh} ;;
            fish) cat ${completionScripts.fish} ;;
            nu | nushell) cat ${completionScripts.nushell} ;;
            -h | --help) echo "Usage: lets completions <bash|zsh|fish|nushell>" ;;
            "")
              echo "Error: missing shell (bash, zsh, fish or nushell)" >&2
              exit 1
              ;;
            *)
              echo "Error: unknown shell: $shell (expected bash, zsh, fish or nushell)" >&2
              exit 1
              ;;
            esac
          '';
        }
      }/bin/completions";
      meta = {
        description = "Print the shell completion script for the given shell";
      };
    };
  };

  inherit completionScripts;
}
