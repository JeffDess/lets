[
  {
    task = "required";
    args = [
      "--url"
      "empty"
    ];
    status = 1;
    stdout = "";
  }
  {
    task = "required";
    args = [
      "--url"
      ""
    ];
    status = 1;
    stdout = "";
  }
  {
    task = "required";
    args = [
      "--url"
      "docs"
    ];
    stdout = "https://example.com/docs";
  }
  {
    task = "browse";
    stdout = "https://example.com/docs";
  }
  {
    task = "browse";
    args = [ "docs" ];
    stdout = "https://example.com/docs";
  }
  {
    task = "browse";
    args = [ "https://other.example/a b?q=1&x=2" ];
    stdout = "https://other.example/a b?q=1&x=2";
  }
  {
    task = "browse";
    args = [ "chain" ];
    stdout = "docs";
  }
  {
    task = "browse";
    args = [ "literal*" ];
    stdout = ''a 'quote' "double" $HOME $(exit 99) `exit 98` \\ end'';
  }
  {
    task = "browse";
    args = [ "literalX" ];
    stdout = "literalX";
  }
  {
    task = "option";
    unset = [ "LETS_ALIAS_URL" ];
    stdout = "https://example.com/docs";
  }
  {
    task = "option";
    args = [
      "--url"
      "docs"
    ];
    stdout = "https://example.com/docs";
  }
  {
    task = "option";
    args = [ "--url=docs" ];
    stdout = "https://example.com/docs";
  }
  {
    task = "option";
    args = [
      "-u"
      "docs"
    ];
    stdout = "https://example.com/docs";
  }
  {
    task = "option";
    env.LETS_ALIAS_URL = "chain";
    stdout = "docs";
  }
  {
    task = "option";
    args = [
      "--url"
      "raw"
    ];
    env.LETS_ALIAS_URL = "docs";
    stdout = "raw";
  }
  {
    task = "option";
    args = [ "--help" ];
    stdout = ''
      Usage: option [options]
      Options:
        -u, --url <value>     (default: docs)
                chain -> docs
                docs -> https://example.com/docs
                literal* -> a 'quote' "double" $HOME $(exit 99) `exit 98` \\ end'';
  }
]
