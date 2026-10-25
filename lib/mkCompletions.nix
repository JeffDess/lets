{ pkgs }:
{ tasks }:
let
  inherit (pkgs) lib;
  inherit (import ./args.nix { inherit lib; })
    longOf
    isPositional
    isFlag
    choicesOf
    ;

  sortStrings = builtins.sort (a: b: a < b);
  tasksByName = lib.foldl' (acc: t: acc // t) { } (
    lib.mapAttrsToList (name: task: lib.genAttrs ([ name ] ++ (task.aliases or [ ])) (_: task)) tasks
  );
  taskNames = sortStrings (builtins.attrNames tasksByName);

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
      env_file = {
        short = "E";
        description = "Load an env file for this run (repeatable)";
      };
      no_env_files = {
        type = "flag";
        description = "Skip envFiles and secrets.files";
      };
      env = {
        short = "e";
        description = "Set a variable for this run (repeatable)";
      };
      secret = {
        short = "S";
        description = "Decrypt secrets for this run (repeatable)";
      };
    };
  };

  taskCommands = lib.mapAttrsToList (name: task: {
    path = lib.splitString "_" name;
    description = task.description or "";
    args = task.args or { };
  }) tasksByName;

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
      choices = choicesOf a.${n};
      aliases = a.${n}.aliases or { };
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
      choices = choicesOf a.${n};
      aliases = a.${n}.aliases or { };
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

  # Alias choices describe their value; task-name choices describe the task.
  descForChoice = aliases: c: aliases.${c} or (tasksByName.${c}.description or "");

  # NOTE: Only the first positional is completed (see _LETS_POSVAL in run-task.sh).
  firstPositional = path: lib.findFirst (_: true) null (positionals path);
  posChoices =
    path:
    let
      first = firstPositional path;
    in
    if first == null || first.choices == null then [ ] else first.choices;

  valueOptEntries =
    path:
    lib.concatMap (
      o:
      map (t: {
        key = "${keyOf path}##${t}";
        inherit (o) choices aliases;
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
          d = descForChoice (firstPositional path).aliases c;
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
          d = descForChoice e.aliases c;
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
      posChoices
      ;
  };
  inherit baked;
}
