{
  pkgs,
  system,
  self,
  tasks,
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
// (import ./tests.nix { inherit pkgs tasks dotenv-spec; })
// (import ./composition.nix {
  inherit
    pkgs
    system
    self
    nixpkgs
    flake-parts
    ;
})
