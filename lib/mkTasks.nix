def:
let
  self = builtins.mapAttrs (key: task: if task ? __build then task.__build key else task) (
    if builtins.isFunction def then def self else def
  );
in
self
