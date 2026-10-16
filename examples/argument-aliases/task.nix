{ mkTask, ... }:
let
  aliases = {
    docs = "https://example.com/docs";
    chain = "docs";
    "literal*" = ''a 'quote' "double" $HOME $(exit 99) `exit 98` \\ end'';
  };
in
{
  browse = mkTask {
    description = "Resolve URL aliases";
    args.url = {
      type = "positional";
      index = 1;
      default = "docs";
      inherit aliases;
    };
    run = ''printf '%s\n' "$url"'';
  };
  option = mkTask {
    description = "Resolve option aliases";
    args.url = {
      short = "u";
      default = [
        "$LETS_ALIAS_URL"
        "docs"
      ];
      inherit aliases;
    };
    run = ''printf '%s\n' "$url"'';
  };
  positional = mkTask {
    description = "Validate required positionals after resolving aliases";
    args.url = {
      type = "positional";
      index = 1;
      required = true;
      aliases.empty = "";
    };
    run = ''printf '%s\n' "$url"'';
  };
  required = mkTask {
    description = "Validate required values after resolving aliases";
    args.url = {
      required = true;
      aliases = aliases // {
        empty = "";
      };
    };
    run = ''printf '%s\n' "$url"'';
  };
}
