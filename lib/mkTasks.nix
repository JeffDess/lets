{ pkgs }:
import ./mkTasksFromDir.nix {
  inherit pkgs;
  dir = ../tasks;
}
