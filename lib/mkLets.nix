{
  pkgs,
  tasks,
  version ? null,
}:
let
  inherit (pkgs) lib;
  resolvedVersion = if version == null then "0.0.0" else version;
  targets = builtins.attrNames tasks ++ [
    "help"
    "show"
  ];
  comp = import ./mkCompletions.nix { inherit pkgs; } { inherit tasks; };
  header = "TARGETS=(${
    lib.concatMapStringsSep " " lib.escapeShellArg targets
  })\nVERSION=${lib.escapeShellArg resolvedVersion}\n${comp.baked}\n\n";
in
pkgs.writeShellApplication {
  name = "lets";
  text = header + builtins.readFile ../scripts/run-task.sh;
}
