{ mkTask, ... }:
{
  update_flake = mkTask {
    description = "Update flake.lock, and dev/flake.lock when there is one";
    run = builtins.readFile ./update-flake.sh;
  };
}
