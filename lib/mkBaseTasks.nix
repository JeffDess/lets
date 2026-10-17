{
  pkgs,
  envFiles ? [ ],
  secrets ? null,
}:
import ./loadTasks.nix {
  inherit pkgs envFiles secrets;
  src = ../tasks;
}
