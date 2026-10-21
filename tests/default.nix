{ pkgs }:
{
  args = import ./args.nix { inherit pkgs; };
  validate = import ./validate.nix { inherit pkgs; };
  mkTask = import ./mkTask.nix { inherit pkgs; };
  render = import ./render.nix { inherit pkgs; };
  fmt = import ./fmt.nix { inherit pkgs; };
  env = import ./env.nix { inherit pkgs; };
  loadTasks = import ./loadTasks.nix { inherit pkgs; };
  mkCompletions = import ./mkCompletions.nix { inherit pkgs; };
}
