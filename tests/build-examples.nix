{ pkgs }:
let
  inherit (pkgs) lib;
  mkTask = import ../lib/mkTask.nix { inherit pkgs; };
  mkTasks = import ../lib/mkTasks.nix;

  dir = ../examples;
  entries = builtins.readDir dir;
  exNames = builtins.filter (
    n: entries.${n} == "directory" && builtins.pathExists (dir + "/${n}/cases.nix")
  ) (builtins.attrNames entries);

  flatten =
    exName:
    let
      ts = mkTasks (import (dir + "/${exName}/task.nix") { inherit pkgs lib mkTask; });
      cases = import (dir + "/${exName}/cases.nix");
    in
    map (
      c:
      let
        parts =
          (c.args or [ ])
          ++ lib.mapAttrsToList (k: v: "${k}=${v}") (c.env or { })
          ++ map (u: "${u}=(unset)") (c.unset or [ ]);
      in
      {
        name = lib.concatStringsSep " " ([ "${exName}: ${c.task}" ] ++ parts);
        bin = lib.getExe ts.${c.task}.app;
        args = c.args or [ ];
        env = c.env or { };
        unset = c.unset or [ ];
        stdout = c.stdout or null;
        status = c.status or 0;
      }
    ) cases;
in
lib.concatLists (map flatten exNames)
