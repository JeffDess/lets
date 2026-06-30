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

  reserved = [
    "completions"
    "default"
    "help"
    "lets"
    "show"
  ];

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
      perFile = map (name: apply tasks (import (src + "/${name}"))) taskFiles;
      allKeys = lib.concatMap builtins.attrNames perFile;
      dupKeys = lib.unique (lib.filter (k: builtins.length (lib.filter (n: n == k) allKeys) > 1) allKeys);
    in
    lib.throwIf (dupKeys != [ ])
      "lets: task name(s) defined in more than one file: ${lib.concatStringsSep ", " dupKeys}"
      (lib.foldl' (acc: s: acc // s) { } perFile);

  loadPath =
    tasks: if builtins.readFileType src == "directory" then loadDir tasks else apply tasks src;

  result = mkTasks (
    tasks: extraTasks // (if builtins.isPath src then loadPath tasks else apply tasks src)
  );

  reservedUsed = lib.filter (n: builtins.elem n reserved) (builtins.attrNames result);
  reservedMsg =
    "lets: task name(s) reserved by lets builtins: "
    + lib.concatStringsSep ", " reservedUsed
    + " (help/show/completions are flag apps; lets/default are packages)";
in
lib.throwIf (reservedUsed != [ ]) reservedMsg result
