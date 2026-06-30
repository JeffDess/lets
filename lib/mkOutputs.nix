{
  pkgs,
  tasks ? import ./loadTasks.nix {
    inherit pkgs;
    src = ../tasks;
  },
}:
let
  fmtPreamble = import ./fmt.nix { inherit (pkgs) lib; };

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
          excludeShellChecks = [ "SC2329" ];
          text =
            fmtPreamble
            + "\n\n"
            + ''
              task="$*"
              if [ -n "$task" ]; then
                ${taskHelp}
                exit 0
              fi

              printf '\n%s%s lets - A Nix Task Runner%s\n' "$BOLD" "$CYAN" "$RESET"
              printf '%s-------------------------%s\n\n' "$DIM" "$RESET"
              printf '%s%s%sUsage%s\n' "$BOLD" "$UNDERLINE" "$BLUE" "$RESET"
              echo "  lets <task> [args...]"
              echo "  lets -h, --help          Display this help message"
              printf '      %s[task]%s               Show help for a single task\n' "$GREEN" "$RESET"
              echo "  lets -s, --show          Show a task's usage, packages and script"
              printf '      %s<task>%s               The task to show\n' "$GREEN" "$RESET"
              echo "  lets -c, --completions   Print a shell completion script"
              printf '      %s<shell>%s              bash, zsh, fish or nushell\n' "$GREEN" "$RESET"
              echo "  lets -v, --version       Show version, description and repository"
              printf '\n%s%s%sAvailable Tasks%s\n' "$BOLD" "$UNDERLINE" "$BLUE" "$RESET"
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
          excludeShellChecks = [ "SC2329" ];
          text =
            fmtPreamble
            + "\n\n"
            + ''
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
          excludeShellChecks = [ "SC2329" ];
          text =
            fmtPreamble
            + "\n\n"
            + ''
              shell="''${1:-}"
              case "$shell" in
              bash) cat ${completionScripts.bash} ;;
              zsh) cat ${completionScripts.zsh} ;;
              fish) cat ${completionScripts.fish} ;;
              nu | nushell) cat ${completionScripts.nushell} ;;
              -h | --help) echo "Usage: lets completions <bash|zsh|fish|nushell>" ;;
              "")
                error "missing shell (bash, zsh, fish or nushell)"
                exit 1
                ;;
              *)
                error "unknown shell: $shell (expected bash, zsh, fish or nushell)"
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
