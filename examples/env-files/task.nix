{ mkTask, ... }:
{
  layered = mkTask {
    description = "Files load in order and the last one wins; the caller's shell wins over them";
    envFiles = [
      ".env"
      ".prod.env"
    ];
    run = ''echo "''${APP_NAME-}@''${DB_HOST-}"'';
  };

  syntax = mkTask {
    description = "export, quotes, concatenation, escapes and comments follow POSIX sh";
    envFiles = [ "syntax.env" ];
    run = ''printf '%s|' "$EXPORTED" "$QUOTED" "$SINGLE" "$CONCAT" "$ESCAPED" "$COMMENTED"'';
  };

  expansion = mkTask {
    description = "Values expand $VAR and \${VAR:-default}, single quotes stay literal";
    envFiles = [ "expand.env" ];
    run = ''echo "$URL|$PORT|$LITERAL"'';
  };

  required = mkTask {
    description = "\${VAR:?message} fails the task with the message";
    envFiles = [ "required.env" ];
    run = ''echo "$TOKEN"'';
  };

  no_commands = mkTask {
    description = "Command substitution is a parse error and never runs";
    envFiles = [ "subst.env" ];
    run = "echo ran";
  };

  reserved = mkTask {
    description = "PATH, BASH_* and lets' own names are skipped with a warning";
    envFiles = [ "reserved.env" ];
    run = ''echo "$OK"'';
  };

  task_args = mkTask {
    description = "Task arguments are never set from a file";
    args.name.default = "World";
    envFiles = [ "args.env" ];
    run = ''echo "$name $OTHER"'';
  };

  missing = mkTask {
    description = "A missing envFiles entry is skipped with a warning";
    envFiles = [ "nope.env" ];
    run = "echo ran";
  };

  crlf = mkTask {
    description = "CRLF line endings are accepted";
    envFiles = [ "crlf.env" ];
    run = ''echo "$A|$B"'';
  };
}
