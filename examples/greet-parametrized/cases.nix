[
  {
    task = "greet";
    args = [
      "--name"
      "Foo"
    ];
    stdout = "Hello Foo";
  }
  {
    task = "greet";
    args = [
      "-n"
      "Foo"
    ];
    stdout = "Hello Foo";
  }
  {
    task = "greet";
    args = [ "--name=Foo" ];
    stdout = "Hello Foo";
  }
  {
    task = "greet";
    env = {
      USER = "Foo";
    };
    stdout = "Hello Foo";
  }
  {
    task = "greet";
    unset = [ "USER" ];
    stdout = "Hello World";
  }
]
