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

  aliasRender = render {
    tasks.browse = {
      description = "Browse";
      args.url = {
        type = "positional";
        index = 1;
        aliases = {
          docs = "https://example.com/docs";
          literal = tricky;
        };
      };
    };
  };
  tricky = ''Deploy to "prod" with $HOME and $(whoami)'';
in
{
  ### Aliases ###

  testAliasValuesEscapedInHelp = {
    expr = lib.hasInfix (lib.escapeShellArg "          literal -> ${tricky}") aliasRender.helpLines;
    expected = true;
  };

  testAliasesInHelp = {
    expr = lib.hasInfix "docs -> https://example.com/docs" aliasRender.helpLines;
    expected = true;
  };

  testAliasesInShow = {
    expr = lib.hasInfix "docs -> https://example.com/docs" aliasRender.showDispatch;
    expected = true;
  };

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
