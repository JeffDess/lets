{
  pkgs,
  tasks ? import ./mkTasks.nix { inherit pkgs; },
}:
let
  taskNames = builtins.sort builtins.lessThan (builtins.attrNames tasks);

  mkApp = _name: task: {
    type = "app";
    program = pkgs.lib.getExe task.app;
    meta = { inherit (task) description; };
  };

  flagLines =
    flags:
    map (
      fn:
      let
        f = flags.${fn};
        shortCol = if f ? short then "-${f.short}, " else "    ";
        longCol = "--" + builtins.replaceStrings [ "_" ] [ "-" ] fn;
        valCol = if (f.type or "string") == "bool" then "" else " <value>";
        defCol =
          if !(f ? default) || (f.type or "string") == "bool" then
            ""
          else
            let
              d = f.default;
              defaults = builtins.filter (el: el != "" && !(pkgs.lib.hasPrefix "$" el)) (
                map toString (if builtins.isList d then d else [ d ])
              );
            in
            if defaults == [ ] then "" else "  (default: ${pkgs.lib.last defaults})";
        line = "      ${shortCol}${longCol}${valCol}   ${f.description or ""}${defCol}";
      in
      "printf '%s\\n' ${pkgs.lib.escapeShellArg line}"
    ) (builtins.attrNames flags);

  helpLines = pkgs.lib.concatStringsSep "\n" (
    pkgs.lib.concatMap (
      name:
      let
        task = tasks.${name};
        displayName = builtins.replaceStrings [ "_" ] [ " " ] name;
        taskLine = "printf \"  \\033[1;34m%s\\033[0m - %s\\n\" \"${displayName}\" \"${task.description}\"";
      in
      [ taskLine ] ++ flagLines (task.flags or { })
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
