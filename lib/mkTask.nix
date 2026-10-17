{
  pkgs,
  envFiles ? [ ],
  secrets ? null,
}:
let
  inherit (pkgs) lib;
  decoder = import ./secrets.nix { inherit pkgs; } secrets;
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
  secrets ? [ ],
  run,
}:
{
  __build =
    key:
    let
      resolvedName = if name != null then name else key;
      normArgs = args'.normalize args;
      decrypts = decoder != null && ((secretsOk && secrets != [ ]) || decoder.files != [ ]);
      decoderInputs = lib.optional decrypts decoder.package;
      allInputs = runtimeInputs ++ decoderInputs;
      envPreamble = mkEnvPreamble {
        inherit
          envFiles
          decoder
          decrypts
          argNames
          ;
      };
      secretsOk = builtins.isList secrets && builtins.all (s: builtins.isString s && s != "") secrets;
      secretLoads = lib.concatMapStringsSep "\n" (
        n: "_lets_env_secret ${lib.escapeShellArg n} 1 explicit secrets"
      ) (if secretsOk then secrets else [ ]);
      secretErrors =
        lib.optional (!secretsOk) "secrets must be a list of non-empty strings"
        ++ lib.optional (
          secretsOk && secrets != [ ] && decoder == null
        ) "secrets needs a project-wide secrets.command";
      errors =
        validate {
          rawArgs = args;
          inherit normArgs;
        }
        ++ secretErrors
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
      envLoad = lib.concatStringsSep "\n" (
        [
          helpScan
          ""
          "if ! _lets_wants_help \"$@\"; then"
          envPreamble
        ]
        ++ lib.optional (secretsOk && secrets != [ ]) secretLoads
        ++ [ "fi" ]
      );
      argNames = builtins.attrNames normArgs;
    in
    lib.throwIf (errors != [ ]) "mkTask (${resolvedName}): ${lib.concatStringsSep "; " errors}" {
      inherit
        description
        run
        runtimeInputs
        secrets
        ;
      args = normArgs;
      app = pkgs.writeShellApplication {
        name = resolvedName;
        runtimeInputs = allInputs;
        excludeShellChecks = [ "SC2329" ];
        text = lib.concatStringsSep "\n\n" [
          fmtPreamble
          envLoad
          argParser
          run
        ];
      };
    };
}
