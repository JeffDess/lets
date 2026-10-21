{
  pkgs,
  mkTask,
  ...
}:
{
  test = mkTask {
    description = "Run the unit test suite";
    runtimeInputs = [ pkgs.nix-unit ];
    run = builtins.readFile ./test.sh;
  };
}
