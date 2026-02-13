{ pkgs }:
let
  lintTasks = import ../tasks/lint.nix { inherit pkgs; };
in
{
  demo = import ../tasks/demo.nix { inherit pkgs; };
}
// lintTasks
