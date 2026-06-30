{ mkTask, ... }:
{
  dup = mkTask {
    description = "from b";
    run = "true";
  };
}
