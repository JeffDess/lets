[
  {
    task = "greet";
    args = [
      "Foo"
      "Bar"
    ];
    stdout = "Hello Foo (the rest stays in $@: Bar)";
  }
  {
    task = "greet";
    args = [
      "--"
      "Foo"
      "Bar"
    ];
    stdout = "Hello Foo (the rest stays in $@: Bar)";
  }
  {
    task = "greet";
    args = [ ];
    status = 1;
  }
]
