{ pkgs, tasks }:
let
  inherit (pkgs) lib;
  targets = builtins.attrNames tasks ++ [
    "help"
    "show"
  ];
  header = "TARGETS=(${lib.concatMapStringsSep " " lib.escapeShellArg targets})\n\n";
in
pkgs.writeShellApplication {
  name = "lets";
  text = header + builtins.readFile ../scripts/run-task.sh;
}
