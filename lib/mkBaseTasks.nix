{ pkgs }:
import ./loadTasks.nix {
  inherit pkgs;
  src = ../tasks;
}
