{ lib }:
raw:
let
  defaults = import ./secretsDefaults.nix;
  cfg = defaults // raw;
  known = [ "command" ] ++ builtins.attrNames defaults;
  unknown = lib.subtractLists known (builtins.attrNames raw);
  hasCommand = raw ? command;
  commandOk =
    hasCommand
    && (
      builtins.isString raw.command
      || (builtins.isList raw.command && builtins.all builtins.isString raw.command)
    );
  words = s: builtins.filter (w: builtins.isString w && w != "") (builtins.split "[[:space:]]+" s);
  command = if builtins.isList raw.command then raw.command else words raw.command;
  hasSlot = commandOk && builtins.elem "{}" command;
  shellLike =
    commandOk
    && builtins.isString raw.command
    && lib.any (c: lib.hasInfix c raw.command) [
      "'"
      "\""
      "\\"
      "|"
      ";"
      "&"
      "<"
      ">"
      "$"
      "`"
    ];
  inherit (cfg) pattern files onError;
  inputs = cfg.runtimeInputs;
  checks = [
    [
      hasCommand
      "lets: secrets.command is required"
    ]
    [
      (unknown == [ ])
      "lets: unknown secrets attribute(s): ${lib.concatStringsSep ", " unknown}"
    ]
    [
      (!hasCommand || commandOk)
      "lets: secrets.command must be a string or a list of words"
    ]
    [
      (!shellLike)
      "lets: secrets.command is split on spaces, not run by a shell: write it as a list"
    ]
    [
      (!commandOk || shellLike || hasSlot)
      "lets: secrets.command must contain {} as a word of its own"
    ]
    [
      (lib.isFunction inputs || builtins.isList inputs)
      "lets: secrets.runtimeInputs must be a list or a function of pkgs"
    ]
    [
      (builtins.isString pattern && builtins.length (lib.splitString "{name}" pattern) == 2)
      "lets: secrets.pattern must be a string containing {name} once"
    ]
    [
      (builtins.isList files && builtins.all (f: builtins.isString f && f != "") files)
      "lets: secrets.files must be a list of non-empty strings"
    ]
    [
      (builtins.elem onError [
        "fail"
        "warn"
        "ignore"
      ])
      ''lets: secrets.onError must be "fail", "warn" or "ignore"''
    ]
  ];
in
if !builtins.isAttrs raw then
  [ ''lets: secrets must be an attribute set, e.g. { command = "sops -d {}"; }'' ]
else
  map (c: builtins.elemAt c 1) (builtins.filter (c: !(builtins.elemAt c 0)) checks)
