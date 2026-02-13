{ pkgs }:
pkgs.writeShellApplication {
  name = "lets";
  text = builtins.readFile ../scripts/run-task.sh;
}
