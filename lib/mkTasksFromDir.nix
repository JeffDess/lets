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
    acc: name: acc // import (dir + "/${name}") { inherit pkgs tasks; }
  ) extraTasks taskFiles;
in
tasks
