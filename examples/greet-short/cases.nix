[
  {
    task = "greet";
    args = [
      "-u"
      "-e"
    ];
    stdout = "HELLO WORLD!";
  }
  {
    task = "greet";
    args = [ "-eu" ];
    stdout = "HELLO WORLD!";
  }
  {
    task = "greet";
    args = [ "-nFoo" ];
    stdout = "Hello Foo";
  }
  {
    task = "greet";
    args = [ "-eunFoo" ];
    stdout = "HELLO FOO!";
  }
  {
    task = "greet";
    args = [
      "-eun"
      "Foo"
    ];
    stdout = "HELLO FOO!";
  }
  {
    task = "greet";
    args = [
      "-en"
      "-u"
    ];
    stdout = "Hello -u!";
  }
  {
    task = "greet";
    args = [ "-ex" ];
    status = 1;
    stdout = "";
  }
]
