{
  pkgs,
  tasks ? import ./mkTasks.nix { inherit pkgs; },
}:
let
  taskNames = builtins.sort builtins.lessThan (builtins.attrNames tasks);

  mkApp = name: task: {
    type = "app";
    program = "${task.app}/bin/${name}";
    meta = { inherit (task) description; };
  };

  helpLines = pkgs.lib.concatStringsSep "\n" (
    map (
      name:
      let
        task = tasks.${name};
        displayName = builtins.replaceStrings [ "_" ] [ " " ] name;
      in
      "printf \"  \\033[1;34m%s\\033[0m - %s\\n\" \"${displayName}\" \"${task.description}\""
    ) taskNames
  );
in
{
  packages = builtins.mapAttrs (_name: task: task.app) tasks;

  apps = (builtins.mapAttrs mkApp tasks) // {
    help = {
      type = "app";
      program = "${
        pkgs.writeShellApplication {
          name = "help";
          text = ''
            printf "\n\033[1;36m lets - A Nix Task Runner\033[0m\n"
            printf "\033[2m-------------------------\033[0m\n\n"
            printf "\033[1mUsage\033[0m\n"
            echo "  lets <task> [type] [-- task-args]"
            printf "\n\033[1mAvailable Tasks\033[0m\n"
            ${helpLines}
            echo
          '';
        }
      }/bin/help";
      meta = {
        description = "List available tasks";
      };
    };
  };
}
