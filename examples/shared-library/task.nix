{ mkTask, ... }:
let
  # NOTE: Stands in for a module another flake exposes as `<lib>.letsTasks`.
  sharedLib =
    { mkTask, ... }:
    {
      hello = mkTask {
        description = "Greeting shipped by the shared library";
        run = ''echo "Hello from the shared library"'';
      };
    };
in
sharedLib { inherit mkTask; }
// {
  bye = mkTask {
    description = "A task local to this project";
    run = ''echo "Bye from the local project"'';
  };
}
# ↑↑↑ A downstream project flake merges it exactly as shown here. ↑↑↑
