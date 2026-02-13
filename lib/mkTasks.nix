{ pkgs }:
let
  lintTasks = import ../tasks/lint { inherit pkgs; };
in
{
  demo = import ../tasks/demo { inherit pkgs; };
}
// lintTasks
