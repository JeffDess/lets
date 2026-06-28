{ lib }:
let
  args = import ./args.nix { inherit lib; };
  inherit (args) isFlag isPositional longOf;

  esc = lib.escapeShellArg; # Single-quote escaping, for whole bash tokens.

  # Backslash escaping, for embedding inside a double-quoted context (${VAR:-HERE}).
  escDq = lib.escape [
    "\\"
    "\""
    "$"
    "`"
  ];

  defaultElems =
    f:
    let
      d = f.default or "";
    in
    map toString (if builtins.isList d then d else [ d ]);
  isEnvRef = el: lib.hasPrefix "$" el;
  envVarOf = el: lib.removeSuffix "}" (lib.removePrefix "{" (lib.removePrefix "$" el));
  literalDefaults = f: builtins.filter (el: !isEnvRef el) (defaultElems f);
in
{ name, normArgs }:
let
  resolvedName = name;
  argNames = builtins.attrNames normArgs;

  optNames = builtins.filter (n: !isPositional normArgs.${n}) argNames;
  posNames = builtins.sort (a: b: (normArgs.${a}.index or 0) < (normArgs.${b}.index or 0)) (
    builtins.filter (n: isPositional normArgs.${n}) argNames
  );

  # NOTE: Bind -h to --help only when no argument claims the short "h".
  usesShortH = lib.any (n: (normArgs.${n}.short or "") == "h") argNames;
  helpPat = (if usesShortH then "" else "-h|") + "--help";

  valueExpr =
    f:
    let
      envRefs = builtins.filter isEnvRef (defaultElems f);
      defaults = literalDefaults f;
      terminal = escDq (if defaults == [ ] then "" else lib.last defaults);
      chain = lib.foldr (el: acc: "\${" + envVarOf el + ":-" + acc + "}") terminal envRefs;
    in
    "\"" + chain + "\"";

  defDisplay =
    f:
    let
      defaults = builtins.filter (el: el != "") (literalDefaults f);
    in
    if isFlag f || defaults == [ ] then "" else "  (default: ${lib.last defaults})";

  initLines = lib.concatMap (
    n:
    let
      f = normArgs.${n};
      value = if isFlag f then lib.boolToString (f.default or false) else valueExpr f;
    in
    [
      "# shellcheck disable=SC2034"
      "${n}=${value}"
    ]
  ) argNames;

  posPlaceholders = lib.concatStrings (
    map (n: if (normArgs.${n}.required or false) then " <${n}>" else " [${n}]") posNames
  );

  valOptNames = builtins.filter (n: !isFlag normArgs.${n}) optNames;
  flagNames = builtins.filter (n: isFlag normArgs.${n}) optNames;
  usageOptLine =
    n:
    let
      f = normArgs.${n};
      shortCol = if f ? short then "-${f.short}, " else "    ";
      valCol = if isFlag f then "" else " <value>";
      reqCol = if (f.required or false) then "  (required)" else "";
      line = "  ${shortCol}${longOf n}${valCol}   ${f.description or ""}${defDisplay f}${reqCol}";
    in
    "printf '%s\\n' ${esc line}";
  usagePosLine =
    n:
    let
      f = normArgs.${n};
      reqCol = if (f.required or false) then "  (required)" else "";
      line = "      <${n}>   ${f.description or ""}${defDisplay f}${reqCol}";
    in
    "printf '%s\\n' ${esc line}";
  usageLines = [
    "printf '%s\\n' ${esc "Usage: ${resolvedName}${lib.optionalString (optNames != [ ]) " [options]"}${posPlaceholders}"}"
  ]
  ++ lib.optional (valOptNames != [ ]) "printf '%s\\n' ${esc "Options:"}"
  ++ map usageOptLine valOptNames
  ++ lib.optional (flagNames != [ ]) "printf '%s\\n' ${esc "Flags:"}"
  ++ map usageOptLine flagNames
  ++ lib.optional (posNames != [ ]) "printf '%s\\n' ${esc "Arguments:"}"
  ++ map usagePosLine posNames;

  caseClauses = lib.concatMap (
    n:
    let
      f = normArgs.${n};
      long = longOf n;
      pat = (if f ? short then "-${f.short}|" else "") + long;
    in
    if isFlag f then
      [
        "  ${pat})"
        "    # shellcheck disable=SC2034"
        "    ${n}=true"
        "    shift"
        "    ;;"
      ]
    else
      [
        "  ${pat})"
        "    if [ \"$#\" -lt 2 ]; then echo \"Error: $1 requires a value\" >&2; exit 1; fi"
        "    # shellcheck disable=SC2034"
        "    ${n}=\"$2\""
        "    shift 2"
        "    ;;"
        "  ${long}=*)"
        "    # shellcheck disable=SC2034"
        "    ${n}=\"\${1#*=}\""
        "    shift"
        "    ;;"
      ]
  ) optNames;

  positionalBindings = lib.concatMap (
    n:
    let
      f = normArgs.${n};
    in
    [ "# shellcheck disable=SC2034" ]
    ++ (
      if (f.required or false) then
        [
          "if [ \"$#\" -gt 0 ]; then ${n}=\"$1\"; shift; else echo \"Error: <${n}> is required\" >&2; exit 1; fi"
        ]
      else
        [ "if [ \"$#\" -gt 0 ]; then ${n}=\"$1\"; shift; fi" ]
    )
  ) posNames;

  requiredChecks = lib.concatMap (
    n:
    let
      f = normArgs.${n};
    in
    lib.optional (
      (f.required or false) && !isFlag f && !isPositional f
    ) "if [ -z \"\${${n}-}\" ]; then echo \"Error: ${longOf n} is required\" >&2; exit 1; fi"
  ) argNames;
in
lib.concatStringsSep "\n" (
  initLines
  ++ [
    ""
    "while [ \"$#\" -gt 0 ]; do"
    "  case \"$1\" in"
    "  ${helpPat})"
  ]
  ++ map (l: "    " + l) usageLines
  ++ [
    "    exit 0"
    "    ;;"
  ]
  ++ caseClauses
  ++ [
    "  --)"
    "    shift"
    "    break"
    "    ;;"
    "  -*)"
    "    echo \"Error: unknown option: $1\" >&2"
    "    exit 1"
    "    ;;"
    "  *)"
    "    break"
    "    ;;"
    "  esac"
    "done"
  ]
  ++ lib.optional (posNames != [ ]) ""
  ++ positionalBindings
  ++ requiredChecks
)
