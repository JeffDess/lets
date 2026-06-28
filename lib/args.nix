{ lib }:
rec {
  normalize = args: if builtins.isList args then lib.genAttrs args (_: { }) else args;

  typeOf = arg: arg.type or "option";
  isOption = arg: typeOf arg == "option";
  isFlag = arg: typeOf arg == "flag";
  isPositional = arg: typeOf arg == "positional";

  longOf = name: "--" + builtins.replaceStrings [ "_" ] [ "-" ] name;

  split = args: {
    optNames = builtins.filter (n: isOption args.${n}) (builtins.attrNames args);
    flagNames = builtins.filter (n: isFlag args.${n}) (builtins.attrNames args);
    posNames = builtins.sort (a: b: (args.${a}.index or 0) < (args.${b}.index or 0)) (
      builtins.filter (n: isPositional args.${n}) (builtins.attrNames args)
    );
  };
}
