{ pkgs }:
raw:
let
  inherit (pkgs) lib;
  errors = import ./secretsErrors.nix { inherit lib; } raw;
  cfg = import ./secretsDefaults.nix // raw;
  words =
    s:
    map (lib.addContextFrom s) (
      builtins.filter (w: builtins.isString w && w != "") (builtins.split "[[:space:]]+" s)
    );
  command = if builtins.isList cfg.command then cfg.command else words cfg.command;
  inputs = cfg.runtimeInputs;
  arg = w: if w == "{}" then ''"$1"'' else lib.escapeShellArg w;
in
if raw == null then
  null
else
  lib.throwIf (errors != [ ]) (lib.concatStringsSep "\n" errors) {
    inherit (cfg) pattern files onError;
    package = pkgs.writeShellApplication {
      name = "lets-decoder";
      runtimeInputs = if lib.isFunction inputs then inputs pkgs else inputs;
      text = "exec ${lib.concatMapStringsSep " " arg command}";
    };
  }
