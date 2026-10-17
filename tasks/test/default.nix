{
  pkgs,
  mkTask,
  tasks,
  ...
}:
{
  test = mkTask {
    description = "Run the unit test suite";
    runtimeInputs = [
      pkgs.convco
      pkgs.gitMinimal
      pkgs.jq
      tasks.lint_commits.app
    ];
    run = builtins.readFile ./test.sh;
  };
}
