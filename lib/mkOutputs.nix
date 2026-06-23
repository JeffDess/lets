{
  pkgs,
  tasks ? import ./mkTasksFromDir.nix {
    inherit pkgs;
    dir = ../tasks;
  },
}:
let
  esc = pkgs.lib.escapeShellArg;
  taskNames = builtins.sort builtins.lessThan (builtins.attrNames tasks);

  mkApp = _name: task: {
    type = "app";
    program = pkgs.lib.getExe task.app;
    meta = { inherit (task) description; };
  };

  argLines =
    args:
    let
      defColOf =
        f:
        if !(f ? default) || (f.type or "option") == "flag" then
          ""
        else
          let
            d = f.default;
            defaults = builtins.filter (el: el != "" && !(pkgs.lib.hasPrefix "$" el)) (
              map toString (if builtins.isList d then d else [ d ])
            );
          in
          if defaults == [ ] then "" else "  (default: ${pkgs.lib.last defaults})";

      isPos = fn: (args.${fn}.type or "option") == "positional";
      names = builtins.attrNames args;
      optNames = builtins.filter (fn: !isPos fn) names;
      posNames = builtins.sort (a: b: (args.${a}.index or 0) < (args.${b}.index or 0)) (
        builtins.filter isPos names
      );

      optLine =
        fn:
        let
          f = args.${fn};
          shortCol = if f ? short then "-${f.short}, " else "    ";
          longCol = "--" + builtins.replaceStrings [ "_" ] [ "-" ] fn;
          valCol = if (f.type or "option") == "flag" then "" else " <value>";
          line = "      ${shortCol}${longCol}${valCol}   ${f.description or ""}${defColOf f}";
        in
        "printf '%s\\n' ${pkgs.lib.escapeShellArg line}";

      posLine =
        fn:
        let
          f = args.${fn};
          reqCol = if (f.required or false) then "  (required)" else "";
          line = "      <${fn}>   ${f.description or ""}${defColOf f}${reqCol}";
        in
        "printf '%s\\n' ${pkgs.lib.escapeShellArg line}";
    in
    map optLine optNames ++ map posLine posNames;

  taskBlock =
    name:
    let
      task = tasks.${name};
      displayName = builtins.replaceStrings [ "_" ] [ " " ] name;
      taskLine = "printf \"  \\033[1;34m%s\\033[0m - %s\\n\" \"${displayName}\" \"${task.description}\"";
    in
    [ taskLine ] ++ argLines (task.args or { });

  helpLines = pkgs.lib.concatStringsSep "\n" (pkgs.lib.concatMap taskBlock taskNames);

  taskHelp = pkgs.lib.concatStringsSep "\n" (
    [
      "task=\"\${task// /_}\""
      "case \"$task\" in"
    ]
    ++ pkgs.lib.concatMap (
      name: [ "${esc name})" ] ++ map (l: "  " + l) (taskBlock name) ++ [ "  ;;" ]
    ) taskNames
    ++ [
      "*)"
      "  echo \"Error: unknown task: $task\" >&2"
      "  exit 1"
      "  ;;"
      "esac"
    ]
  );
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
            task=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
              -t | --task)
                if [ "$#" -lt 2 ]; then
                  echo "Error: $1 requires a value" >&2
                  exit 1
                fi
                task="$2"
                shift 2
                ;;
              -h | --help)
                echo "Usage: lets help [-t|--task <task>]"
                exit 0
                ;;
              -*)
                echo "Error: unknown option: $1" >&2
                exit 1
                ;;
              *)
                break
                ;;
              esac
            done

            if [ -n "$task" ]; then
              ${taskHelp}
              exit 0
            fi

            printf "\n\033[1;36m lets - A Nix Task Runner\033[0m\n"
            printf "\033[2m-------------------------\033[0m\n\n"
            printf "\033[1mUsage\033[0m\n"
            echo "  lets <task> [args...]"
            echo "  lets help [-t|--task <task>]   Show help for a single task"
            printf "\n\033[1mAvailable Tasks\033[0m\n"
            ${helpLines}
            echo
          '';
        }
      }/bin/help";
      meta = {
        description = "List available tasks";
      };
    };
  };
}
