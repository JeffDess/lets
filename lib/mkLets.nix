{
  pkgs,
  tasks,
  version ? null,
}:
let
  inherit (pkgs) lib;
  resolvedVersion = if version == null then "0.0.0" else version;
  targets = builtins.attrNames tasks;
  comp = import ./mkCompletions.nix { inherit pkgs; } { inherit tasks; };
  fmtPreamble = import ./fmt.nix { inherit lib; };
  header = "TARGETS=(${
    lib.concatMapStringsSep " " lib.escapeShellArg targets
  })\nVERSION=${lib.escapeShellArg resolvedVersion}\n${comp.baked}\n\n";
in
pkgs.writeShellApplication {
  name = "lets";
  excludeShellChecks = [ "SC2329" ];
  text = header + fmtPreamble + "\n\n" + builtins.readFile ../scripts/run-task.sh;
}
