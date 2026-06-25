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

  sgr = {
    reset = 0;
    bold = 1;
    dim = 2;
    italic = 3;
    underline = 4;
    black = 30;
    red = 31;
    green = 32;
    yellow = 33;
    blue = 34;
    magenta = 35;
    cyan = 36;
    white = 37;
  };
  fmtStyles = [
    "bold"
    "dim"
    "italic"
    "underline"
  ];
  fmtColors = [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"
  ];

  constLines = lib.concatLists (
    lib.mapAttrsToList (n: code: [
      "# shellcheck disable=SC2034"
      "${lib.toUpper n}=\"$(_lets_sgr ${toString code})\""
    ]) sgr
  );

  singleFns = lib.mapAttrsToList (n: code: "${n}() { _lets_emit ${toString code} \"$@\"; }") (
    lib.filterAttrs (n: _: n != "reset") sgr
  );

  comboFns = lib.concatMap (
    s:
    map (c: "${s}_${c}() { _lets_emit '${toString sgr.${s}};${toString sgr.${c}}' \"$@\"; }") fmtColors
  ) fmtStyles;

  logLevels = {
    error = "red";
    warn = "yellow";
    info = "green";
    debug = "blue";
    trace = "cyan";
  };
  logFns = lib.mapAttrsToList (
    n: color: "${n}() { printf '%s: %s\\n' \"$(${color} ${lib.toUpper n})\" \"$*\"; }"
  ) logLevels;

  fmtBindings = lib.concatStringsSep "\n" (constLines ++ singleFns ++ comboFns ++ logFns);
  fmtPreamble = builtins.readFile ../scripts/fmt.sh + "\n" + fmtBindings;
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
      isPositional = f: (f.type or "option") == "positional";
      longOf = n: "--" + builtins.replaceStrings [ "_" ] [ "-" ] n;

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
        ++ lib.optional (posNames != [ ]) ""
        ++ positionalBindings
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

      validTypes = [
        "option"
        "flag"
        "positional"
      ];
      badTypes = builtins.filter (
        n: (normArgs.${n} ? type) && !(builtins.elem normArgs.${n}.type validTypes)
      ) argNames;

      # Positional-specific validation.
      posDefs = builtins.filter (n: isPositional normArgs.${n}) argNames;
      posMissingIndex = builtins.filter (n: !(normArgs.${n} ? index)) posDefs;
      posBadIndex = builtins.filter (
        n: (normArgs.${n} ? index) && !(builtins.isInt normArgs.${n}.index && normArgs.${n}.index >= 1)
      ) posDefs;
      posWithShort = builtins.filter (n: normArgs.${n} ? short) posDefs;
      posIdxSorted = builtins.sort (a: b: a < b) (map (n: normArgs.${n}.index) posDefs);
      posNotContiguous =
        posMissingIndex == [ ]
        && posBadIndex == [ ]
        && posIdxSorted != lib.genList (i: i + 1) (builtins.length posDefs);

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
            "duplicate short name(s): ${lib.concatStringsSep ", " (map (s: "-${toString s}") dupShorts)}"
        ++
          lib.optional (badTypes != [ ])
            "invalid 'type' (allowed: ${lib.concatStringsSep ", " validTypes}): ${
              lib.concatStringsSep ", " (map (n: "${n}=${builtins.toJSON normArgs.${n}.type}") badTypes)
            }"
        ++ lib.optional (
          posMissingIndex != [ ]
        ) "positional argument(s) missing 'index': ${lib.concatStringsSep ", " posMissingIndex}"
        ++ lib.optional (
          posBadIndex != [ ]
        ) "positional 'index' must be an integer >= 1: ${lib.concatStringsSep ", " posBadIndex}"
        ++ lib.optional (
          posWithShort != [ ]
        ) "positional argument(s) cannot take a 'short': ${lib.concatStringsSep ", " posWithShort}"
        ++ lib.optional posNotContiguous "positional 'index' values must be contiguous starting at 1 (got: ${lib.concatStringsSep ", " (map toString posIdxSorted)})";
    in
    lib.throwIf (errors != [ ]) "mkTask (${resolvedName}): ${lib.concatStringsSep "; " errors}" {
      inherit description run runtimeInputs;
      args = normArgs;
      app = pkgs.writeShellApplication {
        name = resolvedName;
        inherit runtimeInputs;
        excludeShellChecks = [ "SC2329" ];
        text = fmtPreamble + "\n\n" + argParser + "\n\n" + run;
      };
    };
}
