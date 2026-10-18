let
  layers = {
    ".env" = "APP_NAME=demo\nDB_HOST=localhost\n";
    ".prod.env" = "DB_HOST=prod.example.com\n";
  };
  expand = {
    "expand.env" =
      "HOST=db\nPORT=\${PORT:-5432}\nURL=\"https://$HOST:$PORT/app\"\nLITERAL='\${HOST}'\n";
  };
  required."required.env" = "TOKEN=\${TOKEN:?set TOKEN or use -S dev}\n";
  reserved."reserved.env" = "PATH=/nowhere\nBASH_ENV=/evil\n_lets_x=1\nOK=1\n";
  args."args.env" = "name=fromfile\nOTHER=ok\n";
in
[
  {
    task = "layered";
    files = layers;
    stdout = "demo@prod.example.com";
    stderr = "";
  }
  {
    task = "layered";
    files = layers;
    env.DB_HOST = "shell";
    stdout = "demo@shell";
    stderr = "";
  }
  {
    task = "layered";
    files = layers;
    env.DB_HOST = "localhost";
    stdout = "demo@localhost";
    stderr = "";
  }
  {
    task = "layered";
    files = layers;
    env.LETS_ENV_VARS = "DB_HOST=cli";
    stdout = "demo@cli";
    stderr = "";
  }
  {
    task = "layered";
    files = layers;
    env.LETS_NO_ENV_FILES = "1";
    stdout = "@";
    stderr = "";
  }
  {
    task = "syntax";
    files."syntax.env" = ''
      # comment lines and blank lines are ignored

      export EXPORTED=yes
      QUOTED="hello world"
      SINGLE='a # b'
      CONCAT=a'b'"c"
      ESCAPED="say \"hi\""
      COMMENTED=value # after whitespace, # starts a comment
    '';
    stdout = ''yes|hello world|a # b|abc|say "hi"|value|'';
    stderr = "";
  }
  {
    task = "expansion";
    files = expand;
    stdout = "https://db:5432/app|5432|\${HOST}";
    stderr = "";
  }
  {
    task = "expansion";
    files = expand;
    env.PORT = "6000";
    stdout = "https://db:6000/app|6000|\${HOST}";
    stderr = "";
  }
  {
    task = "required";
    files = required;
    status = 1;
    stdout = "";
    stderr = "required.env:1: set TOKEN or use -S dev (from envFiles)";
  }
  {
    task = "required";
    files = required;
    env.TOKEN = "t";
    stdout = "t";
    stderr = "";
  }
  {
    task = "no_commands";
    files."subst.env" = "A=$(touch pwned)\n";
    status = 1;
    stdout = "";
    stderr = "subst.env:1: command substitution and arithmetic are not supported (from envFiles)";
  }
  {
    task = "reserved";
    files = reserved;
    stdout = "1";
    stderr = "PATH is reserved, skipped";
  }
  {
    task = "reserved";
    files = reserved;
    stdout = "1";
    stderr = "BASH_ENV is reserved, skipped";
  }
  {
    task = "reserved";
    files = reserved;
    stdout = "1";
    stderr = "_lets_x is reserved, skipped";
  }
  {
    task = "task_args";
    files = args;
    stdout = "World ok";
    stderr = "name is reserved, skipped";
  }
  {
    task = "task_args";
    files = args;
    args = [
      "--name"
      "cli"
    ];
    stdout = "cli ok";
    stderr = "name is reserved, skipped";
  }
  {
    task = "missing";
    stdout = "ran";
    stderr = "nope.env not found, skipped (from envFiles)";
  }
  {
    task = "crlf";
    files."crlf.env" = "A=1\r\nB=\"two words\"\r\n";
    stdout = "1|two words";
    stderr = "";
  }
]
