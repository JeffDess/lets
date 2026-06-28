{ pkgs }:
{ tasks }:
let
  inherit (pkgs) lib;

  sortStrings = builtins.sort (a: b: a < b);
  taskNames = sortStrings (builtins.attrNames tasks);
  longOf = n: "--" + builtins.replaceStrings [ "_" ] [ "-" ] n;
  isPositional = a: (a.type or "option") == "positional";
  isFlag = a: (a.type or "option") == "flag";

  #
  # MODEL
  #

  # Global lets flags live at the root path.
  rootCommand = {
    path = [ ];
    description = "lets - A Nix Task Runner";
    args = {
      completions = {
        short = "c";
        choices = [
          "bash"
          "fish"
          "nushell"
          "zsh"
        ];
        description = "Print a shell completion script";
      };
      help = {
        short = "h";
        choices = taskNames;
        description = "Display help, optionally for a single task";
      };
      show = {
        short = "s";
        choices = taskNames;
        description = "Show a task's usage, packages and script";
      };
      version = {
        type = "flag";
        short = "v";
        description = "Show version, description and repository";
      };
    };
  };

  taskCommands = lib.mapAttrsToList (name: task: {
    path = lib.splitString "_" name;
    description = task.description or "";
    args = task.args or { };
  }) tasks;

  commands = [ rootCommand ] ++ taskCommands;

  commandAt = path: lib.findFirst (c: c.path == path) null commands;
  argsOf =
    path:
    let
      c = commandAt path;
    in
    if c == null then { } else c.args;

  # Child sub-command words available after `path`.
  subWords =
    path:
    let
      n = builtins.length path;
      deeper = builtins.filter (c: builtins.length c.path > n && lib.take n c.path == path) commands;
    in
    sortStrings (lib.unique (map (c: builtins.elemAt c.path n) deeper));

  isCommand = path: commandAt path != null;

  options =
    path:
    let
      a = argsOf path;
      names = builtins.filter (n: !isPositional a.${n}) (builtins.attrNames a);
    in
    map (n: {
      long = longOf n;
      short = a.${n}.short or null;
      takesValue = !isFlag a.${n};
      choices = a.${n}.choices or null;
      description = a.${n}.description or "";
    }) names;

  positionals =
    path:
    let
      a = argsOf path;
      pos = builtins.filter (n: isPositional a.${n}) (builtins.attrNames a);
      sorted = builtins.sort (x: y: (a.${x}.index or 0) < (a.${y}.index or 0)) pos;
    in
    map (n: {
      name = n;
      description = a.${n}.description or "";
      required = a.${n}.required or false;
      choices = a.${n}.choices or null;
    }) sorted;

  #
  # SHARED RENDERING DATA
  #
  keyOf = path: lib.concatStringsSep " " ([ "lets" ] ++ path);
  prefixesOf = p: map (k: lib.take k p) (lib.range 0 (builtins.length p));
  allNodes = lib.unique (lib.concatMap (c: prefixesOf c.path) commands);
  commandPaths = map (c: c.path) commands;

  descOfPath =
    path:
    let
      c = commandAt path;
    in
    if c == null then "" else c.description;

  descForChoice = c: if tasks ? ${c} then tasks.${c}.description or "" else "";

  posChoices =
    path:
    let
      withChoices = builtins.filter (p: p.choices != null) (positionals path);
    in
    if withChoices == [ ] then [ ] else (lib.head withChoices).choices;

  valueOptEntries =
    path:
    lib.concatMap (
      o:
      map (t: {
        key = "${keyOf path}##${t}";
        inherit (o) choices;
      }) ([ o.long ] ++ lib.optional (o.short != null) "-${o.short}")
    ) (builtins.filter (o: o.takesValue) (options path));

  ac = builtins.replaceStrings [ "\\" "'" ] [ "\\\\" "\\'" ];
  blockOf = entries: lib.concatMapStringsSep "\\n" (e: "${ac e.v}\\t${ac e.d}") entries;

  nodePairs = map (n: { k = keyOf n; }) allNodes;
  optneedsPairs = lib.concatMap (path: map (e: { k = e.key; }) (valueOptEntries path)) commandPaths;

  subPairs = builtins.filter (p: p.block != "") (
    map (n: {
      k = keyOf n;
      block = blockOf (
        map (w: {
          v = w;
          d = descOfPath (n ++ [ w ]);
        }) (subWords n)
      );
    }) allNodes
  );
  optPairs = builtins.filter (p: p.block != "") (
    map (path: {
      k = keyOf path;
      block = blockOf (
        lib.concatMap (
          o:
          map (t: {
            v = t;
            d = o.description;
          }) ([ o.long ] ++ lib.optional (o.short != null) "-${o.short}")
        ) (options path)
      );
    }) commandPaths
  );
  posvalPairs = builtins.filter (p: p.block != "") (
    map (path: {
      k = keyOf path;
      block = blockOf (
        map (c: {
          v = c;
          d = descForChoice c;
        }) (posChoices path)
      );
    }) commandPaths
  );
  optvalPairs = lib.concatMap (
    path:
    map (e: {
      k = e.key;
      block = blockOf (
        map (c: {
          v = c;
          d = descForChoice c;
        }) e.choices
      );
    }) (builtins.filter (e: e.choices != null) (valueOptEntries path))
  ) commandPaths;

  bq = s: "\"" + s + "\"";
  mkMarker =
    name: pairs: "declare -A ${name}=(" + lib.concatMapStrings (p: " [${bq p.k}]=1") pairs + " )";
  mkBlocks =
    name: pairs:
    "declare -A ${name}=(" + lib.concatMapStrings (p: " [${bq p.k}]=$'${p.block}'") pairs + " )";

  baked = lib.concatStringsSep "\n" [
    (mkMarker "_LETS_NODE" nodePairs)
    (mkBlocks "_LETS_SUB" subPairs)
    (mkBlocks "_LETS_OPT" optPairs)
    (mkBlocks "_LETS_POSVAL" posvalPairs)
    (mkMarker "_LETS_OPTNEEDS" optneedsPairs)
    (mkBlocks "_LETS_OPTVAL" optvalPairs)
  ];
in
{
  model = {
    inherit
      subWords
      isCommand
      options
      positionals
      ;
  };
  inherit baked;
}
