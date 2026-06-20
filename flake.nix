{
  description = "lets - A Nix task runner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkTasks = import ./lib/mkTasks.nix;
      mkTasksFromDir = import ./lib/mkTasksFromDir.nix;
      mkOutputs = import ./lib/mkOutputs.nix;
      mkLets = import ./lib/mkLets.nix;
      tasks = mkTasks { inherit pkgs; };
      taskOutputs = mkOutputs { inherit pkgs tasks; };
      runTask = mkLets { inherit pkgs; };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [ runTask ];
        };
      };

      apps.${system} = taskOutputs.apps;

      packages.${system} = {
        default = runTask;
        lets = runTask;
      };

      lib.${system} = {
        inherit
          mkTasks
          mkOutputs
          mkLets
          mkTasksFromDir
          ;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        demo = pkgs.runCommand "check-demo" { } ''
          ${taskOutputs.packages.demo}/bin/demo
          touch "$out"
        '';
        lint = pkgs.runCommand "check-lint" { src = self; } ''
          cp -r "$src" source
          chmod -R +w source
          cd source || exit
          ${taskOutputs.packages.lint}/bin/lint
          touch "$out"
        '';
      };
    };
}
