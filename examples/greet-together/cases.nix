[
  {
    task = "greet";
    args = [ ];
    stdout = "Hello World!";
  }
  {
    task = "greet";
    args = [
      "--firstname"
      "Foo"
    ];
    stdout = "Hello Foo!";
  }
  {
    task = "greet";
    args = [
      "--firstname"
      "Foo"
      "--uppercase"
    ];
    stdout = "HELLO FOO!";
  }
  {
    task = "greet";
    args = [
      "--firstname"
      "Foo"
      "--lastname"
      "Bar"
    ];
    stdout = "Hello Foo Bar!";
  }
]
