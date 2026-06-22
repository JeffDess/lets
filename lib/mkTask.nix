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
  flags ? { },
  runtimeInputs ? [ ],
  run,
}:
{
  __build =
    key:
    let
      resolvedName = if name != null then name else key;
      normFlags = if builtins.isList flags then lib.genAttrs flags (_: { }) else flags;
      flagNames = builtins.attrNames normFlags;

      isBool = f: (f.type or "string") == "bool";
      longOf = n: "--" + builtins.replaceStrings [ "_" ] [ "-" ] n;

      # NOTE: Bind -h to --help only when no flag claims the short "h".
      usesShortH = lib.any (n: (normFlags.${n}.short or "") == "h") flagNames;
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
        if isBool f || defaults == [ ] then "" else "  (default: ${lib.last defaults})";

      initLines = lib.concatMap (
        n:
        let
          f = normFlags.${n};
          value = if isBool f then lib.boolToString (f.default or false) else valueExpr f;
        in
        [
          "# shellcheck disable=SC2034"
          "${n}=${value}"
        ]
      ) flagNames;

      usageLines = [
        "printf '%s\\n' ${esc "Usage: ${resolvedName} [flags]"}"
      ]
      ++ lib.optional (flagNames != [ ]) "printf '%s\\n' ${esc "Flags:"}"
      ++ map (
        n:
        let
          f = normFlags.${n};
          shortCol = if f ? short then "-${f.short}, " else "    ";
          valCol = if isBool f then "" else " <value>";
          reqCol = if (f.required or false) then "  (required)" else "";
          line = "  ${shortCol}${longOf n}${valCol}   ${f.description or ""}${defDisplay f}${reqCol}";
        in
        "printf '%s\\n' ${esc line}"
      ) flagNames;

      caseClauses = lib.concatMap (
        n:
        let
          f = normFlags.${n};
          long = longOf n;
          pat = (if f ? short then "-${f.short}|" else "") + long;
        in
        if isBool f then
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
      ) flagNames;

      requiredChecks = lib.concatMap (
        n:
        let
          f = normFlags.${n};
        in
        lib.optional (
          (f.required or false) && !isBool f
        ) "if [ -z \"\${${n}-}\" ]; then echo \"Error: ${longOf n} is required\" >&2; exit 1; fi"
      ) flagNames;

      flagParser = lib.concatStringsSep "\n" (
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
          "    echo \"Error: unknown flag: $1\" >&2"
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
      shortOf = n: normFlags.${n}.short or null;
      withShort = builtins.filter (n: shortOf n != null) flagNames;
      shorts = map shortOf withShort;
      listDupNames =
        if builtins.isList flags then lib.unique (builtins.filter (x: occurs x flags > 1) flags) else [ ];
      badNames = builtins.filter (n: builtins.match "[a-zA-Z_][a-zA-Z0-9_]*" n == null) flagNames;
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
        ) "duplicate flag name(s): ${lib.concatStringsSep ", " listDupNames}"
        ++ lib.optional (
          badNames != [ ]
        ) "invalid flag name(s) (need a bash identifier): ${lib.concatStringsSep ", " badNames}"
        ++
          lib.optional (badShorts != [ ])
            "short must be a single letter: ${
              lib.concatStringsSep ", " (map (n: "${n}=${builtins.toJSON (shortOf n)}") badShorts)
            }"
        ++
          lib.optional (dupShorts != [ ])
            "duplicate short flag(s): ${lib.concatStringsSep ", " (map (s: "-${toString s}") dupShorts)}";
    in
    lib.throwIf (errors != [ ]) "mkTask (${resolvedName}): ${lib.concatStringsSep "; " errors}" {
      inherit description;
      flags = normFlags;
      app = pkgs.writeShellApplication {
        name = resolvedName;
        inherit runtimeInputs;
        text = flagParser + "\n\n" + run;
      };
    };
}
