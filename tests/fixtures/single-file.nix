{ mkTask, ... }:
{
  one = mkTask {
    description = "first";
    run = "true";
  };
  two = mkTask {
    description = "second";
    run = "true";
  };
}
