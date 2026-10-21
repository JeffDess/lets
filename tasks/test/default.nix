{
  pkgs,
  mkTask,
  ...
}:
{
  test = mkTask {
    description = "Run the unit, shell and example tests";
    runtimeInputs = [
      pkgs.gitMinimal
      pkgs.nix-unit
    ];
    run = builtins.readFile ./test.sh;
  };
}
