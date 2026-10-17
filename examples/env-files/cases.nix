[
  {
    task = "layered";
    stdout = "demo@prod.example.com";
    stderr = "";
  }
  {
    task = "layered";
    env.DB_HOST = "shell";
    stdout = "demo@shell";
    stderr = "";
  }
  {
    task = "layered";
    env = {
      DB_HOST = "shell";
      POSIXLY_CORRECT = "1";
    };
    stdout = "demo@shell";
    stderr = "";
  }
  {
    task = "layered_override";
    env.DB_HOST = "shell";
    stdout = "demo@prod.example.com";
    stderr = "";
  }
  {
    task = "layered";
    env.LETS_ENV_VARS = "DB_HOST=cli";
    stdout = "demo@cli";
    stderr = "";
  }
  {
    task = "layered";
    env = {
      DB_HOST = "shell";
      LETS_ENV_VARS = "DB_HOST=cli";
    };
    stdout = "demo@cli";
  }
  {
    task = "layered_override";
    env.LETS_ENV_VARS = "DB_HOST=cli";
    stdout = "demo@cli";
  }
  {
    task = "layered";
    env.LETS_ENV_VARS = ''DB_HOST= "q" '';
    stdout = ''demo@ "q" '';
  }
  {
    task = "layered";
    env.LETS_ENV_VARS = "DB_HOST=";
    stdout = "demo@";
  }
  {
    task = "layered";
    env.LETS_ENV_VARS = "PATH=/nowhere";
    status = 1;
    stdout = "";
    stderr = "PATH is reserved (from -e or LETS_ENV_VARS)";
  }
  {
    task = "layered";
    env.LETS_ENV_VARS = "_LETS_ENV_SPACE=x";
    status = 1;
    stdout = "";
    stderr = "_LETS_ENV_SPACE is reserved (from -e or LETS_ENV_VARS)";
  }
  {
    task = "task_args";
    env.LETS_ENV_VARS = "name=cli";
    status = 1;
    stdout = "";
    stderr = "name is reserved (from -e or LETS_ENV_VARS)";
  }
  {
    task = "syntax";
    stdout = "yes|hello world|a # b|$(echo pwned)|ok|x|";
    stderr = "";
  }
  {
    task = "values";
    stdout = ''abc==|http://x?a=b|v # note|||  p  |s|a\b\\c|ok|'';
    stderr = "";
  }
  {
    task = "missing";
    status = 1;
    stdout = "";
    stderr = "does-not-exist.env not found";
  }
  {
    task = "broken_link";
    status = 1;
    stderr = "broken.env is a broken symlink";
  }
  {
    task = "bad_key";
    status = 1;
    stderr = "invalid variable name '1BAD'";
  }
  {
    task = "no_equals";
    status = 1;
    stderr = "missing '='";
  }
  {
    task = "reserved";
    stdout = "1 intact";
    stderr = "PATH is reserved, skipped";
  }
  {
    task = "special";
    stdout = "literal bar";
    stderr = "RANDOM is reserved, skipped";
  }
  {
    task = "read_only";
    stdout = "FOO=bar";
    stderr = "UID is reserved, skipped";
  }
  {
    task = "local_names";
    stdout = "kept|kept|kept|kept|";
    stderr = "";
  }
  {
    task = "reexport";
    env.DB_HOST = "shell";
    stdout = "prod.example.com";
    stderr = "";
  }
  {
    task = "unset_caller";
    env.DB_HOST = "shell";
    stdout = "prod.example.com";
    stderr = "";
  }
  {
    task = "locked_dir";
    status = 1;
    stderr = "locked/s.env is not a readable file";
  }
  {
    task = "unicode_space";
    env.LC_ALL = "C.UTF-8";
    status = 1;
    stderr = "invalid variable name";
  }
  {
    task = "bom";
    stdout = "ok";
    stderr = "";
  }
  {
    task = "unset_secret";
    stdout = "clean";
    stderr = "";
  }
  {
    task = "declared";
    stdout = "literal bar h 1 unset";
    stderr = "N is reserved, skipped";
  }
  {
    task = "declared_local";
    stdout = "prod.example.com";
    stderr = "";
  }
  {
    task = "task_args";
    args = [
      "--name"
      "cli"
    ];
    stdout = "cli false ok";
    stderr = "name is reserved, skipped";
  }
  {
    task = "task_args";
    stdout = "World false ok";
    stderr = "loud is reserved, skipped";
  }
  {
    task = "nameref";
    stdout = "intact";
    stderr = "target is reserved, skipped";
  }
  {
    task = "shell_vars";
    stdout = "1 unset unset unset";
    stderr = "FUNCNEST is reserved, skipped";
  }
  {
    task = "shell_vars";
    stdout = "1 unset unset unset";
    stderr = "LINENO is reserved, skipped";
  }
  {
    task = "shell_vars";
    stdout = "1 unset unset unset";
    stderr = "EPOCHSECONDS is reserved, skipped";
  }
  {
    task = "partial";
    stdout = "unset";
    stderr = "partial.env:2: missing '='";
  }
  {
    task = "multiline";
    status = 1;
    stderr = "multiline.env:1: unmatched quote";
  }
  {
    task = "quoted_comment";
    status = 1;
    stderr = "quoted-comment.env:1: text after the closing quote, inline comments are not supported";
  }
  {
    task = "mixed_quote";
    status = 1;
    stderr = "mixed-quote.env:1: unmatched quote";
  }
  {
    task = "internal_names";
    stdout = "[p]";
    stderr = "_LETS_ENV_SPACE is reserved, skipped";
  }
  {
    task = "internal_names";
    stdout = "[p]";
    stderr = "_lets_trim is reserved, skipped";
  }
  {
    task = "edges";
    stdout = "1|t|e|2|";
    stderr = "";
  }
  {
    task = "empty_key";
    status = 1;
    stderr = "invalid variable name ''";
  }
  {
    task = "options";
    env.DB_HOST = "shell";
    stdout = "prod.example.com 1";
    stderr = "";
  }
  {
    task = "unknown_option";
    status = 1;
    stderr = "unknown option '-x'";
  }
  {
    task = "no_file";
    status = 1;
    stderr = "usage: load_env";
  }
  {
    task = "directory";
    status = 1;
    stderr = ". is not a readable file";
  }
  {
    task = "unreadable";
    status = 1;
    stderr = "unreadable.env is not a readable file";
  }
]
