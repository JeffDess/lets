{ pkgs }:
let
  mkTask = import ../lib/mkTask.nix { inherit pkgs; };
  build = cfg: (mkTask cfg).__build "ignored";
in
{
  tasks = {
    lint = build {
      description = "Run all lint tasks";
      args.verbose = {
        type = "flag";
        short = "v";
        description = "Verbose output";
      };
      run = "true";
    };
    lint_nix = build {
      description = "Lint Nix files";
      run = "true";
    };
    "lint_nix-bash" = build {
      description = "Lint bash in Nix";
      run = "true";
    };
    version = build {
      description = "Bump the version";
      args.dry_run = {
        type = "flag";
        description = "Plan only";
      };
      run = "true";
    };
    demo = build {
      description = "Demo task";
      args = {
        locale = {
          short = "l";
          default = "en_US";
          description = "Locale";
        };
        name = {
          type = "positional";
          index = 1;
          description = "Name to greet";
        };
      };
      run = "true";
    };
  };
}
