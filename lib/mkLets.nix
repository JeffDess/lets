{
  pkgs,
  tasks,
  version ? null,
  secrets ? null,
}:
let
  inherit (pkgs) lib;
  decoder = import ./secrets.nix { inherit pkgs; } secrets;
  secretsPattern = (if decoder == null then import ./secretsDefaults.nix else decoder).pattern;
  resolvedVersion = if version == null then "0.0.0" else version;
  targets = builtins.attrNames tasks;
  comp = import ./mkCompletions.nix { inherit pkgs; } { inherit tasks; };
  fmtPreamble = import ./fmt.nix { inherit lib; };
  header = "TARGETS=(${
    lib.concatMapStringsSep " " lib.escapeShellArg targets
  })\nVERSION=${lib.escapeShellArg resolvedVersion}\nSECRETS_PATTERN=${lib.escapeShellArg secretsPattern}\n${comp.baked}\n\n";
in
pkgs.writeShellApplication {
  name = "lets";
  runtimeInputs = lib.optional (decoder != null) decoder.package;
  excludeShellChecks = [ "SC2329" ];
  text = header + fmtPreamble + "\n\n" + builtins.readFile ../scripts/run-task.sh;
}
