{ pkgs }:
import ../lib/mkLets.nix {
  inherit pkgs;
  inherit (import ./fixture.nix { inherit pkgs; }) tasks;
  version = "0.0.0";
}
