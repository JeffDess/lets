{ pkgs }:
let
  inherit (pkgs) lib;
  render = import ../lib/render.nix { inherit pkgs; };

  helpLinesOf =
    description:
    (render {
      tasks.deploy = {
        inherit description;
        run = "true";
        runtimeInputs = [ ];
        args = { };
      };
    }).helpLines;

  tricky = ''Deploy to "prod" with $HOME and $(whoami)'';
in
{
  ### Help description escaping ###

  testHelpDescriptionEscaped = {
    expr = lib.hasInfix (lib.escapeShellArg tricky) (helpLinesOf tricky);
    expected = true;
  };

  testHelpDescriptionNotInterpolatedRaw = {
    expr = lib.hasInfix ("\"" + tricky) (helpLinesOf tricky);
    expected = false;
  };
}
