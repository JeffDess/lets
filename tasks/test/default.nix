{ pkgs, mkTask, ... }:
{
  test = mkTask {
    description = "Run the unit test suite";
    runtimeInputs = [ pkgs.jq ];
    run = builtins.readFile ./test.sh;
  };
}
