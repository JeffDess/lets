{
  pkgs,
  dir,
  extraTasks ? { },
}:
let
  inherit (pkgs) lib;
  entries = builtins.readDir dir;
  isTask =
    name: type:
    (type == "regular" && name != "default.nix" && lib.hasSuffix ".nix" name)
    || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
  taskFiles = lib.filter (name: isTask name entries.${name}) (builtins.attrNames entries);
  tasks = lib.foldl' (
    acc: name:
    let
      mkTask = import ./mkTask.nix {
        inherit pkgs;
        defaultName = lib.removeSuffix ".nix" name;
      };
    in
    acc
    // import (dir + "/${name}") {
      inherit
        pkgs
        lib
        tasks
        mkTask
        ;
    }
  ) extraTasks taskFiles;
in
tasks
