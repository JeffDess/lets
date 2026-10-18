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
  projectEnvFiles = envFiles;
  mkEnvPreamble = import ./env.nix { inherit lib; };
  envFilesErrors = import ./envFiles.nix { inherit lib; };
in
{
  name ? null,
  description,
  args ? { },
  runtimeInputs ? [ ],
  envFiles ? [ ],
  secrets ? [ ],
  run,
}:
{
  __build =
    key:
    let
      resolvedName = if name != null then name else key;
      normArgs = args'.normalize args;
      argNames = builtins.attrNames normArgs;
      secretsOk = builtins.isList secrets && builtins.all (s: builtins.isString s && s != "") secrets;
      taskSecrets = if secretsOk then secrets else [ ];
      decrypts = decoder != null && (taskSecrets != [ ] || decoder.files != [ ]);
      decoderInputs = lib.optional decrypts decoder.package;
      allInputs = runtimeInputs ++ decoderInputs;
      envPreamble = mkEnvPreamble {
        envFiles = projectEnvFiles;
        taskEnvFiles = envFiles;
        secrets = taskSecrets;
        inherit
          decoder
          decrypts
          argNames
          key
          ;
      };
      secretErrors =
        lib.optional (!secretsOk) "secrets must be a list of non-empty strings"
        ++ lib.optional (
          taskSecrets != [ ] && decoder == null
        ) "secrets needs a project-wide secrets.command";
      errors =
        validate {
          rawArgs = args;
          inherit normArgs;
        }
        ++ secretErrors
        ++ map (lib.removePrefix "lets: ") (envFilesErrors projectEnvFiles ++ envFilesErrors envFiles);
      parser = buildParser {
        name = resolvedName;
        inherit normArgs;
      };
      envLoad = lib.concatStringsSep "\n" [
        parser.wantsHelp
        ""
        "if ! _lets_wants_help \"$@\"; then"
        envPreamble
        "fi"
      ];
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
          parser.parse
          run
        ];
      };
    };
}
