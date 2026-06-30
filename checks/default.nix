{
  pkgs,
  system,
  self,
  nixpkgs,
  flake-parts,
  taskOutputs,
}:
(import ./tasks.nix {
  inherit
    pkgs
    system
    self
    taskOutputs
    ;
})
// (import ./tests.nix { inherit pkgs; })
// (import ./composition.nix {
  inherit
    pkgs
    system
    self
    nixpkgs
    flake-parts
    ;
})
