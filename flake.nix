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
      mkTask = import ./lib/mkTask.nix;
      mkTasks = import ./lib/mkTasks.nix;
      mkTasksFromDir = import ./lib/mkTasksFromDir.nix;
      mkOutputs = import ./lib/mkOutputs.nix;
      mkLets = import ./lib/mkLets.nix;
      mkBaseTasks = import ./lib/mkBaseTasks.nix;
      tasks = mkBaseTasks { inherit pkgs; };
      taskOutputs = mkOutputs { inherit pkgs tasks; };
      runTask = mkLets { inherit pkgs tasks; };
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
          mkTask
          mkTasks
          mkOutputs
          mkLets
          mkTasksFromDir
          mkBaseTasks
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
