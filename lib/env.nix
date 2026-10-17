{ lib }:
{
  envFiles,
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
  protected = [ "PATH" ] ++ shellVars ++ map lib.toUpper sgrNames ++ argNames;
  protectedDecl = lib.concatMapStrings (n: "[${n}]=1 ") protected;
in
builtins.readFile ../scripts/env.sh
+ "declare -A _LETS_ENV_PROTECTED=(${protectedDecl})"
+ lib.optionalString (envFiles != [ ]) ''

  # shellcheck disable=SC1003,SC1110,SC1111,SC1112,SC2016,SC2088
  _lets_env_autoload ${lib.escapeShellArgs envFiles}''
