{
  pkgs,
  mkTask,
  ...
}:
{
  test = mkTask {
    description = "Run the unit, shell and example tests";
    runtimeInputs = [ pkgs.nix-unit ];
    run = builtins.readFile ./test.sh;
  };
}
