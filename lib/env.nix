{ lib }:
{
  envFiles,
  decoder,
  decrypts ? false,
  argNames ? [ ],
}:
let
  sgrNames = builtins.attrNames (import ./sgr.nix);
  shellVars = [
    "CDPATH"
    "EPOCHREALTIME"
    "EPOCHSECONDS"
    "EXECIGNORE"
    "FUNCNEST"
    "GLOBIGNORE"
    "GLOBSORT"
    "IFS"
    "LINENO"
    "OLDPWD"
    "POSIXLY_CORRECT"
    "PS4"
    "PWD"
    "SHLVL"
    "TMOUT"
  ];
  protected = [
    "PATH"
    "LETS_ENV_FILES"
    "LETS_NO_ENV_FILES"
    "LETS_ENV_VARS"
    "LETS_SECRETS"
    "LETS_SECRETS_DIR"
    "LETS_ENV_SOURCES"
  ]
  ++ shellVars
  ++ map lib.toUpper sgrNames
  ++ argNames;
  protectedDecl = lib.concatMapStrings (n: "[${n}]=1 ") protected;
  words = xs: lib.concatMapStringsSep " " lib.escapeShellArg xs;
  decoderBin = if decoder == null then "" else "${decoder.package}/bin/lets-decoder";
  decoderRef = if decrypts then decoderBin else builtins.unsafeDiscardStringContext decoderBin;
  decoderDrv = builtins.unsafeDiscardOutputDependency decoder.package.drvPath;
  cfg = if decoder == null then import ./secretsDefaults.nix else decoder;
  decoderVars =
    "_LETS_SECRET_BIN=${if decoder == null then "''" else decoderRef}\n"
    + "_LETS_SECRET_DRV=${if decoder == null || decrypts then "''" else decoderDrv}\n"
    + "_LETS_SECRET_PATTERN=${lib.escapeShellArg cfg.pattern}\n"
    + "_LETS_SECRET_ON_ERROR=${lib.escapeShellArg cfg.onError}\n"
    + "_LETS_SECRET_FILES=(${words cfg.files})\n";
in
builtins.readFile ../scripts/env.sh
+ "declare -A _LETS_ENV_PROTECTED=(${protectedDecl})\n"
+ decoderVars
+ "# shellcheck disable=SC1003,SC1110,SC1111,SC1112,SC2016,SC2088,SC2119\n"
+ lib.concatStringsSep " " ([ "_lets_env_autoload" ] ++ map lib.escapeShellArg envFiles)
