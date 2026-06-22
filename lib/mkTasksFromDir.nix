{
  pkgs,
  dir,
  extraTasks ? { },
}:
let
  inherit (pkgs) lib;
  mkTask = import ./mkTask.nix { inherit pkgs; };
  mkTasks = import ./mkTasks.nix;
  entries = builtins.readDir dir;
  isTask =
    name: type:
    (type == "regular" && name != "default.nix" && lib.hasSuffix ".nix" name)
    || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
  taskFiles = lib.filter (name: isTask name entries.${name}) (builtins.attrNames entries);
in
mkTasks (
  tasks:
  lib.foldl' (
    acc: name:
    acc
    // import (dir + "/${name}") {
      inherit
        pkgs
        lib
        mkTask
        tasks
        ;
    }
  ) extraTasks taskFiles
)
