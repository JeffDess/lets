{
  pkgs,
  self,
  taskOutputs,
}:
{
  demo = pkgs.runCommand "check-demo" { } ''
    # shellcheck disable=SC2154
    ${taskOutputs.packages.demo}/bin/demo
    touch "$out"
  '';
  colors = pkgs.runCommand "check-colors" { } ''
    # shellcheck disable=SC2154
    bin=${taskOutputs.packages.colors}/bin/colors
    esc=$'\033['
    # Capture to a variable (no pipe) so the task is never killed by SIGPIPE.
    # runCommand has no tty, so color is off unless FORCE_COLOR is set.
    # Merge stderr: error/warn log there, the other levels to stdout.
    forced="$(FORCE_COLOR=1 "$bin" 2>&1)"

    case $forced in
    *"$esc"*) echo "✅ ANSI codes emitted when forced" ;;
    *)
      echo "❌ expected ANSI codes with FORCE_COLOR=1" >&2
      exit 1
      ;;
    esac

    plain="$("$bin" 2>&1)"

    case $plain in
    *"$esc"*)
      echo "❌ ANSI codes leaked when not a tty" >&2
      exit 1
      ;;
    *) echo "✅ plain text when not a tty" ;;
    esac

    # Log helpers: the level word is colored by severity; the message stays
    # plain (the reset closes before the colon).
    for spec in "ERROR 31" "WARN 33" "INFO 32" "DEBUG 34" "TRACE 36"; do
      level=''${spec%% *}
      code=''${spec##* }
      want="$esc$code""m$level$esc""0m: "
      case $forced in
      *"$want"*) echo "✅ $level colored ($code) when forced" ;;
      *)
        echo "❌ expected colored $level ($code) when forced" >&2
        exit 1
        ;;
      esac
      case $plain in
      *"$level: "*) echo "✅ $level plain when not a tty" ;;
      *)
        echo "❌ expected '$level: ' in plain output" >&2
        exit 1
        ;;
      esac
    done

    touch "$out"
  '';
  lint = pkgs.runCommand "check-lint" { src = self; } ''
    cp -r "$src" source
    chmod -R +w source
    cd source || exit
    ${taskOutputs.packages.lint}/bin/lint
    touch "$out"
  '';
  release-flow = pkgs.runCommand "check-release-flow" { nativeBuildInputs = [ pkgs.git ]; } ''
    export HOME="$TMPDIR"
    git config --global user.email ci@lets.test
    git config --global user.name ci
    git config --global init.defaultBranch main

    mkdir repo && cd repo
    git init -q
    cp ${../cliff.toml} cliff.toml
    printf '{\n  version = "1.2.3";\n}\n' >flake.nix
    git add .
    git commit -q -m "feat: a feature"
    git tag -a v1.2.3 -m v1.2.3
    git commit -q --allow-empty -m "feat: unreleased work"

    head_before="$(git rev-parse HEAD)"
    forced="$(${taskOutputs.packages.version}/bin/version minor --dry-run)"
    case $forced in
    *"1.2.3 -> 1.3.0"*) echo "✅ version minor --dry-run computes the bump" ;;
    *)
      echo "❌ version minor --dry-run output: $forced" >&2
      exit 1
      ;;
    esac
    auto="$(${taskOutputs.packages.version}/bin/version --dry-run)"
    case $auto in
    *"1.2.3 -> 1.3.0"*) echo "✅ version --dry-run auto-detects the bump" ;;
    *)
      echo "❌ version --dry-run (auto) output: $auto" >&2
      exit 1
      ;;
    esac
    if [ "$(git rev-parse HEAD)" != "$head_before" ]; then
      echo "❌ version --dry-run mutated the repository" >&2
      exit 1
    fi

    git checkout -q v1.2.3
    notes="$(GITHUB_REF_NAME=v1.2.3 ${taskOutputs.packages.release}/bin/release --dry-run)"
    case $notes in
    *"### Features"*) echo "✅ release --dry-run renders notes" ;;
    *)
      echo "❌ release --dry-run output: $notes" >&2
      exit 1
      ;;
    esac
    case $notes in
    *"## ["*)
      echo "❌ release notes still contain a version heading" >&2
      exit 1
      ;;
    *) echo "✅ release notes omit the redundant version heading" ;;
    esac

    if GITHUB_REF_NAME=v9.9.9 ${taskOutputs.packages.release}/bin/release --dry-run 2>/dev/null; then
      echo "❌ release accepted a tag/version mismatch" >&2
      exit 1
    fi
    echo "✅ release rejects tag/version mismatch"

    touch "$out"
  '';
}
