{
  pkgs,
}:
let
  inherit (pkgs) lib;
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
{
  name ? null,
  description,
  args ? { },
  runtimeInputs ? [ ],
  run,
}:
{
  __build =
    key:
    let
      resolvedName = if name != null then name else key;
      normArgs = if builtins.isList args then lib.genAttrs args (_: { }) else args;
      argNames = builtins.attrNames normArgs;

      isFlag = f: (f.type or "option") == "flag";
      longOf = n: "--" + builtins.replaceStrings [ "_" ] [ "-" ] n;

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

      usageLines = [
        "printf '%s\\n' ${esc "Usage: ${resolvedName} [options]"}"
      ]
      ++ lib.optional (argNames != [ ]) "printf '%s\\n' ${esc "Options:"}"
      ++ map (
        n:
        let
          f = normArgs.${n};
          shortCol = if f ? short then "-${f.short}, " else "    ";
          valCol = if isFlag f then "" else " <value>";
          reqCol = if (f.required or false) then "  (required)" else "";
          line = "  ${shortCol}${longOf n}${valCol}   ${f.description or ""}${defDisplay f}${reqCol}";
        in
        "printf '%s\\n' ${esc line}"
      ) argNames;

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
            "    ${n}=true"
            "    shift"
            "    ;;"
          ]
        else
          [
            "  ${pat})"
            "    if [ \"$#\" -lt 2 ]; then echo \"Error: $1 requires a value\" >&2; exit 1; fi"
            "    ${n}=\"$2\""
            "    shift 2"
            "    ;;"
            "  ${long}=*)"
            "    ${n}=\"\${1#*=}\""
            "    shift"
            "    ;;"
          ]
      ) argNames;

      requiredChecks = lib.concatMap (
        n:
        let
          f = normArgs.${n};
        in
        lib.optional (
          (f.required or false) && !isFlag f
        ) "if [ -z \"\${${n}-}\" ]; then echo \"Error: ${longOf n} is required\" >&2; exit 1; fi"
      ) argNames;

      argParser = lib.concatStringsSep "\n" (
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
        ++ requiredChecks
      );

      #
      # VALIDATION
      #
      occurs = x: l: builtins.length (builtins.filter (y: y == x) l);
      shortOf = n: normArgs.${n}.short or null;
      withShort = builtins.filter (n: shortOf n != null) argNames;
      shorts = map shortOf withShort;
      listDupNames =
        if builtins.isList args then lib.unique (builtins.filter (x: occurs x args > 1) args) else [ ];
      badNames = builtins.filter (n: builtins.match "[a-zA-Z_][a-zA-Z0-9_]*" n == null) argNames;
      badShorts = builtins.filter (
        n:
        let
          s = shortOf n;
        in
        !(builtins.isString s && builtins.match "[a-zA-Z]" s != null)
      ) withShort;
      dupShorts = lib.unique (builtins.filter (s: occurs s shorts > 1) shorts);

      errors =
        lib.optional (
          listDupNames != [ ]
        ) "duplicate argument name(s): ${lib.concatStringsSep ", " listDupNames}"
        ++ lib.optional (
          badNames != [ ]
        ) "invalid argument name(s) (need a bash identifier): ${lib.concatStringsSep ", " badNames}"
        ++
          lib.optional (badShorts != [ ])
            "short must be a single letter: ${
              lib.concatStringsSep ", " (map (n: "${n}=${builtins.toJSON (shortOf n)}") badShorts)
            }"
        ++
          lib.optional (dupShorts != [ ])
            "duplicate short name(s): ${lib.concatStringsSep ", " (map (s: "-${toString s}") dupShorts)}";
    in
    lib.throwIf (errors != [ ]) "mkTask (${resolvedName}): ${lib.concatStringsSep "; " errors}" {
      inherit description;
      args = normArgs;
      app = pkgs.writeShellApplication {
        name = resolvedName;
        inherit runtimeInputs;
        text = argParser + "\n\n" + run;
      };
    };
}
