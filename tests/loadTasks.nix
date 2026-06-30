{ pkgs }:
let
  loadTasks = import ../lib/loadTasks.nix;
  loads =
    src:
    (builtins.tryEval (
      builtins.attrNames (loadTasks {
        inherit pkgs src;
      })
    )).success;
  inlineTask =
    name:
    (
      { mkTask, ... }:
      {
        ${name} = mkTask {
          description = "x";
          run = "true";
        };
      }
    );
in
{
  ### Reserved task names (clash with lets builtins) ###

  testReservedHelpRejected = {
    expr = loads (inlineTask "help");
    expected = false;
  };

  testReservedLetsRejected = {
    expr = loads (inlineTask "lets");
    expected = false;
  };

  testNonReservedAccepted = {
    expr = loads (inlineTask "greet");
    expected = true;
  };

  ### Duplicate task names across files ###

  testDuplicateAcrossFilesRejected = {
    expr = loads ./fixtures/dup-tasks;
    expected = false;
  };
}
