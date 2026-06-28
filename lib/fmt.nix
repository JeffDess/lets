{ lib }:
let
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
in
builtins.readFile ../scripts/fmt.sh + "\n" + fmtBindings
