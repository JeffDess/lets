{ lib }:
envFiles:
let
  inStore = f: builtins.isPath f || (builtins.isString f && builtins.hasContext f);
  name = "[A-Za-z_][A-Za-z0-9_]*";
  unexpanded =
    f:
    builtins.isString f
    && lib.any (p: builtins.isString p && lib.hasInfix "$" p) (
      builtins.split "\\$(\\{${name}}|${name})" f
    );
in
if !builtins.isList envFiles then
  [ ''lets: envFiles must be a list, e.g. [ ".env" ]'' ]
else
  lib.optional (builtins.any inStore envFiles) (
    ''lets: envFiles must be strings (".env"), not paths: ''
    + "they are read at runtime, not copied to the store"
  )
  ++ lib.optional (builtins.any (
    f: !builtins.isPath f && !builtins.isString f
  ) envFiles) "lets: envFiles must be a list of strings"
  ++ lib.optional (builtins.elem "" envFiles) "lets: envFiles entries cannot be empty"
  ++ map (f: "lets: envFiles entry '${f}' can only expand $VAR and \${VAR}") (
    builtins.filter unexpanded envFiles
  )
