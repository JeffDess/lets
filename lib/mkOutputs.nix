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

  reqColOf = f: if (f.required or false) then "  (required)" else "";

  plain = line: "printf '%s\\n' ${esc line}";

  splitArgs =
    args:
    let
      typeOf = fn: args.${fn}.type or "option";
      names = builtins.attrNames args;
    in
    {
      optNames = builtins.filter (fn: typeOf fn == "option") names;
      flagNames = builtins.filter (fn: typeOf fn == "flag") names;
      posNames = builtins.sort (a: b: (args.${a}.index or 0) < (args.${b}.index or 0)) (
        builtins.filter (fn: typeOf fn == "positional") names
      );
    };

  argNameCol =
    args: fn:
    let
      f = args.${fn};
    in
    if (f.type or "option") == "positional" then
      "<${fn}>"
    else
      let
        shortCol = if f ? short then "-${f.short}, " else "    ";
        longCol = "--" + builtins.replaceStrings [ "_" ] [ "-" ] fn;
        valCol = if (f.type or "option") == "flag" then "" else " <value>";
      in
      "${shortCol}${longCol}${valCol}";

  detailLine =
    indent: args: fn:
    let
      f = args.${fn};
    in
    "printf '${indent}\\033[32m%s\\033[0m   %s\\033[2m%s\\033[0m%s\\n' ${esc (argNameCol args fn)} ${esc (f.description or "")} ${esc (defColOf f)} ${esc (reqColOf f)}";

  argLines =
    args:
    let
      s = splitArgs args;
    in
    map (detailLine "      " args) (s.optNames ++ s.flagNames ++ s.posNames);

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
      name: [ "${esc name})" ] ++ map (l: "  " + l) (usageSections name) ++ [ "  ;;" ]
    ) taskNames
    ++ [
      "*)"
      "  echo \"Error: unknown task: $task\" >&2"
      "  exit 1"
      "  ;;"
      "esac"
    ]
  );

  titleLine = t: "printf '\\033[1;4;34m%s\\033[0m\\n' ${esc t}";
  section =
    title: content:
    [
      "echo"
      (titleLine title)
    ]
    ++ content;

  usageSections =
    name:
    let
      args = tasks.${name}.args or { };
      s = splitArgs args;
      suffix =
        pkgs.lib.optionalString ((s.optNames ++ s.flagNames) != [ ]) " [options]"
        + pkgs.lib.concatStrings (
          map (fn: if (args.${fn}.required or false) then " <${fn}>" else " [${fn}]") s.posNames
        );
    in
    section "Usage" [ (plain "  ${name}${suffix}") ]
    ++ pkgs.lib.optionals (s.optNames != [ ]) (
      section "Options" (map (detailLine "  " args) s.optNames)
    )
    ++ pkgs.lib.optionals (s.flagNames != [ ]) (
      section "Flags" (map (detailLine "  " args) s.flagNames)
    )
    ++ pkgs.lib.optionals (s.posNames != [ ]) (
      section "Arguments" (map (detailLine "  " args) s.posNames)
    );

  showLines =
    name:
    let
      task = tasks.${name};
      pnames = map (p: pkgs.lib.getName p) (task.runtimeInputs or [ ]);
      pkgItems = if pnames == [ ] then [ (plain "  (none)") ] else map (n: plain "  • ${n}") pnames;
      scriptFile = pkgs.writeText "${name}-run" (task.run or "");
    in
    usageSections name
    ++ section "Packages" pkgItems
    ++ section "Script" [ "bat -l bash --style=numbers --paging=never ${scriptFile}" ];

  showDispatch = pkgs.lib.concatStringsSep "\n" (
    [
      "task=\"\${1// /_}\""
      "case \"$task\" in"
    ]
    ++ pkgs.lib.concatMap (
      name: [ "${esc name})" ] ++ map (l: "  " + l) (showLines name) ++ [ "  ;;" ]
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
            printf "\033[1;4;34mUsage\033[0m\n"
            echo "  lets <task> [args...]"
            echo "  lets help, -h, --help    Display this help message"
            printf '      \033[32m-t, --task <value>\033[0m   Show help for a single task\n'
            echo "  lets show <task>         Show a task's usage, packages and script"
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
              echo "Usage: lets show <task>" >&2
              exit 1
            fi

            ${showDispatch}
          '';
        }
      }/bin/show";
      meta = {
        description = "Show a task's usage, packages and script";
      };
    };
  };
}
