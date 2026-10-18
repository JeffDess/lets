{ lib }:
{
  envFiles,
  taskEnvFiles ? [ ],
  secrets ? [ ],
  decoder,
  decrypts ? false,
  argNames ? [ ],
  key ? "",
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
  reserved = [
    "_lets_*"
    "_LETS_*"
    "_dotenv_*"
    "DOTENV_ERROR"
    "DOTENV_ERROR_KIND"
    "DOTENV_SKIPPED"
    "BASH_*"
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
  call = name: xs: "  ${name}${lib.concatMapStrings (x: " " + lib.escapeShellArg x) xs}\n";
  decoderBin = if decoder == null then "" else "${decoder.package}/bin/lets-decoder";
  decoderRef = if decrypts then decoderBin else builtins.unsafeDiscardStringContext decoderBin;
  decoderDrv = builtins.unsafeDiscardStringContext decoder.package.drvPath;
  cfg = if decoder == null then import ./secretsDefaults.nix else decoder;
  decoderVars =
    "_LETS_SECRET_BIN=${if decoder == null then "''" else decoderRef}\n"
    + "_LETS_SECRET_DRV=${if decoder == null || decrypts then "''" else decoderDrv}\n"
    + "_LETS_TASK_KEY='${lib.replaceStrings [ "'" ] [ "'\\''" ] key}'\n"
    + "_LETS_SECRET_PATTERN=${lib.escapeShellArg cfg.pattern}\n"
    + "_LETS_SECRET_ON_ERROR=${lib.escapeShellArg cfg.onError}\n"
    + "_LETS_SECRET_FILES=(${lib.escapeShellArgs cfg.files})\n";
in
builtins.readFile ../scripts/dotenv.sh
+ builtins.readFile ../scripts/env.sh
+ "_LETS_ENV_RESERVED=(${lib.escapeShellArgs reserved})\n"
+ decoderVars
+ "# shellcheck disable=SC1003,SC1110,SC1111,SC1112,SC2016,SC2088,SC2119\n"
+ "{\n"
+ call "_lets_env_no_files_check" [ ]
+ call "_lets_env_vars" [ ]
+ call "_lets_env_files" envFiles
+ call "_lets_env_secret_files" [ ]
+ call "_lets_env_files" taskEnvFiles
+ call "_lets_env_task_secrets" secrets
+ call "_lets_env_cli" [ ]
+ call "_lets_env_export" [ ]
+ "}"
