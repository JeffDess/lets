{ pkgs }:
let
  inherit (pkgs) lib;
  args' = import ./args.nix { inherit lib; };
  inherit (args')
    isFlag
    isPositional
    longOf
    split
    ;
  esc = lib.escapeShellArg;

  defColOf =
    f:
    if !(f ? default) || isFlag f then
      ""
    else
      let
        d = f.default;
        defaults = builtins.filter (el: el != "" && !(lib.hasPrefix "$" el)) (
          map toString (if builtins.isList d then d else [ d ])
        );
      in
      if defaults == [ ] then "" else "  (default: ${lib.last defaults})";

  reqColOf = f: if (f.required or false) then "  (required)" else "";

  plain = line: "printf '%s\\n' ${esc line}";

  argNameCol =
    args: fn:
    let
      f = args.${fn};
    in
    if isPositional f then
      "    <${fn}>"
    else
      let
        shortCol = if f ? short then "-${f.short}, " else "    ";
        longCol = longOf fn;
        valCol = if isFlag f then "" else " <value>";
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
      s = split args;
    in
    map (detailLine "      " args) (s.optNames ++ s.flagNames ++ s.posNames);

  titleLine = t: "printf '\\033[1;4;34m%s\\033[0m\\n' ${esc t}";
  section =
    title: content:
    [
      "echo"
      (titleLine title)
    ]
    ++ content;

  dispatch =
    taskNames: linesOf:
    lib.concatStringsSep "\n" (
      [
        "task=\"\${task// /_}\""
        "case \"$task\" in"
      ]
      ++ lib.concatMap (
        name: [ "${esc name})" ] ++ map (l: "  " + l) (linesOf name) ++ [ "  ;;" ]
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
{ tasks }:
let
  taskNames = builtins.sort builtins.lessThan (builtins.attrNames tasks);

  taskBlock =
    name:
    let
      task = tasks.${name};
      displayName = builtins.replaceStrings [ "_" ] [ " " ] name;
      taskLine = "printf \"  \\033[1;34m%s\\033[0m - %s\\n\" \"${displayName}\" \"${task.description}\"";
    in
    [ taskLine ] ++ argLines (task.args or { });

  usageSections =
    name:
    let
      args = tasks.${name}.args or { };
      s = split args;
      suffix =
        lib.optionalString ((s.optNames ++ s.flagNames) != [ ]) " [options]"
        + lib.concatStrings (
          map (fn: if (args.${fn}.required or false) then " <${fn}>" else " [${fn}]") s.posNames
        );
    in
    section "Usage" [ (plain "  ${name}${suffix}") ]
    ++ lib.optionals (s.optNames != [ ]) (section "Options" (map (detailLine "  " args) s.optNames))
    ++ lib.optionals (s.flagNames != [ ]) (section "Flags" (map (detailLine "  " args) s.flagNames))
    ++ lib.optionals (s.posNames != [ ]) (section "Arguments" (map (detailLine "  " args) s.posNames));

  showLines =
    name:
    let
      task = tasks.${name};
      pnames = map (p: lib.getName p) (task.runtimeInputs or [ ]);
      pkgItems = if pnames == [ ] then [ (plain "  (none)") ] else map (n: plain "  • ${n}") pnames;
      scriptFile = pkgs.writeText "${name}-run" (task.run or "");
    in
    usageSections name
    ++ section "Packages" pkgItems
    ++ section "Script" [ "bat -l bash --style=numbers --paging=never ${scriptFile}" ];
in
{
  helpLines = lib.concatStringsSep "\n" (lib.concatMap taskBlock taskNames);
  taskHelp = dispatch taskNames usageSections;
  showDispatch = dispatch taskNames showLines;
}
