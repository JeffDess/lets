{ lib }:
let
  sgr = import ./sgr.nix;
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
    n: color:
    let
      toErr = n == "error" || n == "warn";
      colorVar = if toErr then "_lets_color_err" else "_lets_color";
      redir = lib.optionalString toErr " >&2";
    in
    "${n}() { _lets_logline \"\$${colorVar}\" ${toString sgr.${color}} ${lib.toUpper n} \"$@\"${redir}; }"
  ) logLevels;

  fmtBindings = lib.concatStringsSep "\n" (constLines ++ singleFns ++ comboFns ++ logFns);
in
builtins.readFile ../scripts/fmt.sh + "\n" + fmtBindings
