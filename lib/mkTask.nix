{
  pkgs,
}:
let
  inherit (pkgs) lib;
  args' = import ./args.nix { inherit lib; };
  validate = import ./validate.nix { inherit lib; };
  buildParser = import ./parser.nix { inherit lib; };
  fmtPreamble = import ./fmt.nix { inherit lib; };
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
      normArgs = args'.normalize args;
      errors = validate {
        rawArgs = args;
        inherit normArgs;
      };
      argParser = buildParser {
        name = resolvedName;
        inherit normArgs;
      };
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
