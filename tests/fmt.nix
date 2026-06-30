{ pkgs }:
let
  inherit (pkgs) lib;
  fmt = import ../lib/fmt.nix { inherit (pkgs) lib; };
in
{
  ### Log helpers colorize against the fd they write to ###

  testStderrColorDecisionExists = {
    expr = lib.hasInfix "[ -t 2 ]" fmt;
    expected = true;
  };

  testErrorColorizesOnStderr = {
    expr = lib.hasInfix ''error() { _lets_logline "$_lets_color_err" 31 ERROR "$@" >&2; }'' fmt;
    expected = true;
  };

  testWarnColorizesOnStderr = {
    expr = lib.hasInfix ''warn() { _lets_logline "$_lets_color_err" 33 WARN "$@" >&2; }'' fmt;
    expected = true;
  };

  testInfoColorizesOnStdout = {
    expr = lib.hasInfix ''info() { _lets_logline "$_lets_color" 32 INFO "$@"; }'' fmt;
    expected = true;
  };
}
