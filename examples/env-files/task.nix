{ pkgs, mkTask, ... }:
let
  base = pkgs.writeText "base.env" ''
    # Shared settings
    APP_NAME=demo
    DB_HOST=localhost

    export EXPORTED=yes
    QUOTED="hello world"
    SINGLE='a # b'
    LITERAL=$(echo pwned)
  '';
  prod = pkgs.writeText "prod.env" ''
    DB_HOST=prod.example.com
  '';
  crlf = pkgs.writeText "crlf.env" "CRLF=ok\r\nTRAILING=x   \n";
  values = pkgs.writeText "values.env" ''
    EQ=abc==
    URL=http://x?a=b
    INLINE=v # note
    EMPTY=
    EMPTY_QUOTED=""
    PADDED="  p  "
    SPACED = s
    BS=a\b\\c
    LAST=ok'';
  badKey = pkgs.writeText "bad-key.env" "1BAD=x\n";
  noEquals = pkgs.writeText "no-equals.env" "JUSTAKEY\n";
  reserved = pkgs.writeText "reserved.env" "RED=x\nPATH=/nowhere\nOK=1\n";
  injection = pkgs.writeText "injection.env" "RANDOM=BASH_VERSINFO[$(: >pwned)0]\nFOO=bar\n";
  readOnly = pkgs.writeText "read-only.env" "UID=1000\nFOO=bar\n";
  localNames = pkgs.writeText "local-names.env" "line=kept\nfile=kept\nusage=kept\nkey=kept\n";
  secret = pkgs.writeText "secret.env" "TOKEN=s3cr3t\n";
  declared = pkgs.writeText "declared.env" "N=BASH_VERSINFO[$(: >pwned-declared)0]\nCFG=fromfile\nFOO=bar\n";
  nameref = pkgs.writeText "nameref.env" "target=/nowhere\n";
  partial = pkgs.writeText "partial.env" "FIRST=1\nnot a variable\n";
  multiline = pkgs.writeText "multiline.env" ''
    KEY="-----BEGIN KEY-----
    abc=
    -----END KEY-----"
  '';
  quotedComment = pkgs.writeText "quoted-comment.env" ''
    GREETING="hello" # comment
  '';
  mixedQuote = pkgs.writeText "mixed-quote.env" ''
    GREETING="hello'
  '';
  internal = pkgs.writeText "internal.env" "_LETS_ENV_SPACE=x\n_lets_trim=x\nPADDED=  p  \n";
  argNames = pkgs.writeText "arg-names.env" "name=fromfile\nloud=true\nOTHER=ok\n";
  edges = pkgs.writeText "edges.env" "exportFOO=1\n\tTABBED\t=\tt\t\nexport\tTAB_EXPORT=e\nDUP=1\nDUP=2\n";
  emptyKey = pkgs.writeText "empty-key.env" "=x\n";
  shellVars = pkgs.writeText "shell-vars.env" ''
    BASH_ENV=/nowhere
    IFS=:
    POSIXLY_CORRECT=1
    SHLVL=9
    FUNCNEST=2
    GLOBSORT=-name
    LINENO=99
    EPOCHSECONDS=1
    A=1
  '';
in
{
  layered = mkTask {
    description = "Later files win, the caller's shell wins over files";
    run = ''
      load_env ${base} ${prod}
      echo "$APP_NAME@$DB_HOST"
    '';
  };

  layered_override = mkTask {
    description = "With --override, files win over the caller's shell";
    run = ''
      load_env --override ${base} ${prod}
      echo "$APP_NAME@$DB_HOST"
    '';
  };

  syntax = mkTask {
    description = "export prefix, quotes, literal values, CRLF";
    run = ''
      load_env ${base} ${crlf}
      printf '%s|' "$EXPORTED" "$QUOTED" "$SINGLE" "$LITERAL" \
        "$CRLF" "$TRAILING"
      echo
    '';
  };

  values = mkTask {
    description = "Values keep '=', '#' and backslashes, empty values are set, the last line needs no newline";
    run = ''
      load_env ${values}
      printf '%s|' "$EQ" "$URL" "$INLINE" "''${EMPTY-unset}" "''${EMPTY_QUOTED-unset}" \
        "$PADDED" "$SPACED" "$BS" "$LAST"
      echo
    '';
  };

  missing = mkTask {
    description = "A missing file fails the task";
    run = ''
      load_env ./does-not-exist.env
      echo 'done'
    '';
  };

  broken_link = mkTask {
    description = "A broken symlink fails the task and is named as such";
    runtimeInputs = [ pkgs.coreutils ];
    run = ''
      ln -sf /nowhere/target.env broken.env
      load_env broken.env
    '';
  };

  bad_key = mkTask {
    description = "An invalid variable name fails the task";
    run = "load_env ${badKey}";
  };

  no_equals = mkTask {
    description = "A line without '=' fails the task";
    run = "load_env ${noEquals}";
  };

  reserved = mkTask {
    description = "PATH and preamble names are never overwritten";
    run = ''
      load_env --override ${reserved}
      [ "$PATH" != /nowhere ] && [ "$RED" != x ] && echo "$OK intact"
    '';
  };

  special = mkTask {
    description = "Integer shell variables never evaluate a value";
    run = ''
      load_env ${injection}
      if [ -e pwned ]; then echo executed; else echo "literal $FOO"; fi
    '';
  };

  read_only = mkTask {
    description = "Read-only shell variables are skipped, even with --override";
    run = ''
      load_env --override ${readOnly}
      echo "FOO=$FOO"
    '';
  };

  unset_secret = mkTask {
    description = "An unset value leaves no copy in the environment";
    run = ''
      load_env ${secret}
      unset TOKEN
      if [[ "$(export -p)" == *s3cr3t* ]]; then echo leaked; else echo clean; fi
    '';
  };

  declared = mkTask {
    description = "Variables the task declared with an attribute are never set from a file";
    run = ''
      declare -i N
      declare -A CFG=([host]=h)
      load_env ${declared}
      if [ -e pwned-declared ]; then
        echo executed
      else
        echo "literal $FOO ''${CFG[host]} ''${#CFG[@]} ''${N:-unset}"
      fi
    '';
  };

  declared_local = mkTask {
    description = "A local declared without a value is set from a file";
    run = ''
      f() {
        local DB_HOST
        load_env ${prod}
        echo "$DB_HOST"
      }
      f
    '';
  };

  task_args = mkTask {
    description = "Task arguments are never set from a file, even with --override";
    args.name.default = "World";
    args.loud.type = "flag";
    run = ''
      load_env --override ${argNames}
      echo "$name $loud $OTHER"
    '';
  };

  nameref = mkTask {
    description = "A nameref never redirects a file key to PATH";
    run = ''
      declare -n target=PATH
      load_env ${nameref}
      [ "$target" != /nowhere ] && echo intact
    '';
  };

  shell_vars = mkTask {
    description = "Variables that change how bash runs are never set from a file";
    run = ''
      load_env --override ${shellVars}
      if [[ $IFS == $' \t\n' ]] && [ "$SHLVL" != 9 ]; then
        echo "$A ''${BASH_ENV-unset} ''${POSIXLY_CORRECT-unset} ''${GLOBSORT-unset}"
      fi
    '';
  };

  reexport = mkTask {
    description = "A value the task exported itself is replaced by the file";
    run = ''
      export DB_HOST=custom
      load_env ${prod}
      echo "$DB_HOST"
    '';
  };

  unset_caller = mkTask {
    description = "A caller value the task unset is set by the file";
    run = ''
      unset DB_HOST
      load_env ${prod}
      echo "''${DB_HOST-unset}"
    '';
  };

  locked_dir = mkTask {
    description = "A file in a directory that cannot be searched fails the task";
    runtimeInputs = [ pkgs.coreutils ];
    run = ''
      mkdir -p locked
      printf 'S=1\n' >locked/s.env
      chmod 000 locked
      trap 'chmod 700 locked' EXIT
      load_env locked/s.env
    '';
  };

  unicode_space = mkTask {
    description = "Only ASCII whitespace is trimmed, whatever the locale";
    run = ''
      wide=$'　'
      [ "''${#wide}" = 1 ] || exit 2
      printf 'FOO\xe3\x80\x80=bar\n' >wide.env
      load_env wide.env
      echo "FOO=$FOO"
    '';
  };

  bom = mkTask {
    description = "A UTF-8 byte order mark at the start of a file is ignored";
    run = ''
      printf '\xef\xbb\xbfBOM=ok\n' >bom.env
      load_env bom.env
      echo "$BOM"
    '';
  };

  partial = mkTask {
    description = "A file that fails to parse sets nothing";
    run = ''
      if ! load_env ${partial}; then echo "''${FIRST-unset}"; fi
    '';
  };

  multiline = mkTask {
    description = "A quoted value spanning lines fails the task";
    run = "load_env ${multiline}";
  };

  quoted_comment = mkTask {
    description = "A comment after a quoted value fails the task";
    run = "load_env ${quotedComment}";
  };

  mixed_quote = mkTask {
    description = "A value closed with the other quote fails the task";
    run = "load_env ${mixedQuote}";
  };

  internal_names = mkTask {
    description = "Names used by load_env itself are never set from a file";
    run = ''
      load_env --override ${internal}
      echo "[$PADDED]"
    '';
  };

  edges = mkTask {
    description = "Tabs are trimmed, export needs whitespace, the last duplicate wins";
    run = ''
      load_env ${edges}
      for n in exportFOO TABBED TAB_EXPORT DUP; do printf '%s|' "''${!n}"; done
      echo
    '';
  };

  empty_key = mkTask {
    description = "A line without a name fails the task";
    run = "load_env ${emptyKey}";
  };

  options = mkTask {
    description = "-o is --override, -- ends the options";
    run = ''
      printf 'DASH=1\n' >./-dash.env
      load_env -o -- ${prod} -dash.env
      echo "$DB_HOST $DASH"
    '';
  };

  unknown_option = mkTask {
    description = "An unknown option fails the task";
    run = "load_env -x ${prod}";
  };

  no_file = mkTask {
    description = "load_env without a file fails the task";
    run = "load_env --override";
  };

  directory = mkTask {
    description = "A directory fails the task";
    run = "load_env .";
  };

  unreadable = mkTask {
    description = "A file that cannot be read fails the task";
    runtimeInputs = [ pkgs.coreutils ];
    run = ''
      printf 'S=1\n' >unreadable.env
      chmod 000 unreadable.env
      load_env unreadable.env
    '';
  };

  local_names = mkTask {
    description = "Keys named like load_env's own variables still load";
    run = ''
      load_env ${localNames}
      for n in line file usage key; do printf '%s|' "''${!n}"; done
      echo
    '';
  };
}
