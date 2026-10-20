{
  pkgs,
  system,
  self,
  nixpkgs,
  flake-parts,
  taskOutputs,
  dotenv-spec,
}:
(import ./tasks.nix {
  inherit
    pkgs
    system
    self
    taskOutputs
    ;
})
// (import ./tests.nix { inherit pkgs dotenv-spec; })
// (import ./composition.nix {
  inherit
    pkgs
    system
    self
    nixpkgs
    flake-parts
    ;
})
