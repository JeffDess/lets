{ mkTask, ... }:
{
  colors = mkTask {
    description = "Demo Task: showcase the injected text-formatting helpers";
    run = builtins.readFile ./colors.sh;
  };
}
