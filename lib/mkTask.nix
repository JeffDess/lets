{
  pkgs,
  envFiles ? [ ],
}:
let
  inherit (pkgs) lib;
  args' = import ./args.nix { inherit lib; };
  validate = import ./validate.nix { inherit lib; };
  buildParser = import ./parser.nix { inherit lib; };
  fmtPreamble = import ./fmt.nix { inherit lib; };
  mkEnvPreamble = import ./env.nix { inherit lib; };
  envFilesErrors = import ./envFiles.nix { inherit lib; } envFiles;
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
      envPreamble = mkEnvPreamble { inherit envFiles argNames; };
      errors =
        validate {
          rawArgs = args;
          inherit normArgs;
        }
        ++ map (lib.removePrefix "lets: ") envFilesErrors;
      argParser = buildParser {
        name = resolvedName;
        inherit normArgs;
      };
      helpScan = buildParser {
        name = resolvedName;
        inherit normArgs;
        helpScan = true;
      };
      envLoad = "${helpScan}\n\nif ! _lets_wants_help \"$@\"; then\n${envPreamble}\nfi";
      loadsEnv = envFiles != [ ] || lib.hasInfix "load_env" run;
      argNames = builtins.attrNames normArgs;
    in
    lib.throwIf (errors != [ ]) "mkTask (${resolvedName}): ${lib.concatStringsSep "; " errors}" {
      inherit description run runtimeInputs;
      args = normArgs;
      app = pkgs.writeShellApplication {
        name = resolvedName;
        inherit runtimeInputs;
        excludeShellChecks = [ "SC2329" ];
        text = lib.concatStringsSep "\n\n" (
          [ fmtPreamble ]
          ++ lib.optional loadsEnv envLoad
          ++ [
            argParser
            run
          ]
        );
      };
    };
}
