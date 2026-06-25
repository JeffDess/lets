{
  pkgs,
  src,
  system ? pkgs.stdenv.hostPlatform.system,
  specialArgs ? { },
  extraTasks ? { },
}:
let
  inherit (pkgs) lib;
  mkTask = import ./mkTask.nix { inherit pkgs; };
  mkTasks = import ./mkTasks.nix;

  scope =
    tasks:
    {
      inherit
        pkgs
        lib
        system
        mkTask
        tasks
        ;
    }
    // specialArgs;

  apply = tasks: x: if builtins.isFunction x then x (scope tasks) else x;

  loadDir =
    tasks:
    let
      entries = builtins.readDir src;
      isTask =
        name: type:
        (type == "regular" && name != "default.nix" && lib.hasSuffix ".nix" name)
        || (type == "directory" && builtins.pathExists (src + "/${name}/default.nix"));
      taskFiles = lib.filter (name: isTask name entries.${name}) (builtins.attrNames entries);
    in
    lib.foldl' (acc: name: acc // apply tasks (import (src + "/${name}"))) { } taskFiles;

  loadPath =
    tasks: if builtins.readFileType src == "directory" then loadDir tasks else apply tasks (import src);
in
mkTasks (tasks: extraTasks // (if builtins.isPath src then loadPath tasks else apply tasks src))
