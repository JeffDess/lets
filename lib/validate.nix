{ lib }:
let
  args = import ./args.nix { inherit lib; };
  inherit (args) isPositional;
in
{ rawArgs, normArgs }:
let
  argNames = builtins.attrNames normArgs;

  occurs = x: l: builtins.length (builtins.filter (y: y == x) l);
  shortOf = n: normArgs.${n}.short or null;
  withShort = builtins.filter (n: shortOf n != null) argNames;
  shorts = map shortOf withShort;
  listDupNames =
    if builtins.isList rawArgs then
      lib.unique (builtins.filter (x: occurs x rawArgs > 1) rawArgs)
    else
      [ ];
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
in
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
++ lib.optional posNotContiguous "positional 'index' values must be contiguous starting at 1 (got: ${lib.concatStringsSep ", " (map toString posIdxSorted)})"
