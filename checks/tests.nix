{ pkgs, dotenv-spec }:
{
  dotenv =
    let
      module = ../scripts/dotenv.sh;
      tests = ../tests/dotenv;
    in
    pkgs.runCommand "check-dotenv"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.shellcheck
        ];
      }
      ''
        bash ${tests}/conformance.sh ${module} ${dotenv-spec}/tests/evaluation
        bash ${tests}/extensions.sh ${module}
        bash ${tests}/differential.sh ${module}
        {
          printf '#!/usr/bin/env bash\nset -euo pipefail\necho wrapped\n'
          printf 'if true; then\n'
          tail -n +2 ${module}
          printf 'fi\n'
        } >"$TMPDIR/wrapped.sh"
        shellcheck -s bash -e SC2329 "$TMPDIR/wrapped.sh"
        touch "$out"
      '';
  examples =
    let
      aliasesHelp =
        (import ../lib/mkOutputs.nix {
          inherit pkgs;
          tasks = import ../lib/mkTasks.nix (
            import ../examples/argument-aliases/task.nix {
              inherit pkgs;
              inherit (pkgs) lib;
              mkTask = import ../lib/mkTask.nix { inherit pkgs; };
            }
          );
        }).apps.help.program;
    in
    pkgs.runCommand "check-examples"
      {
        nativeBuildInputs = [ pkgs.jq ];
        casesJson = builtins.toJSON (import ../tests/build-examples.nix { inherit pkgs; });
      }
      ''
        fail=0
        total=0
        report=""
        while read -r c; do
          total=$((total + 1))
          name=$(jq -r '.name' <<<"$c")
          bin=$(jq -r '.bin' <<<"$c")
          expStatus=$(jq -r '.status' <<<"$c")
          hasOut=$(jq -r 'if .stdout == null then "no" else "yes" end' <<<"$c")
          expOut=$(jq -r '.stdout // ""' <<<"$c")
          mapfile -t argv < <(jq -r '.args[]?' <<<"$c")
          mapfile -t envv < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' <<<"$c")
          mapfile -t unsetv < <(jq -r '.unset[]?' <<<"$c")
          unsetargs=()
          for u in "''${unsetv[@]}"; do unsetargs+=(-u "$u"); done
          errf="$TMPDIR/stderr"
          casedir="$TMPDIR/case-$total"
          mkdir -p "$casedir"
          while IFS= read -r -d "" f && IFS= read -r -d "" body; do
            printf '%s' "$body" >"$casedir/$f"
          done < <(jq -j '.files | to_entries[] | "\(.key)\u0000\(.value)\u0000"' <<<"$c")
          if actual=$(cd "$casedir" && env "''${unsetargs[@]}" "''${envv[@]}" \
            "$bin" "''${argv[@]}" 2>"$errf"); then
            code=0
          else
            code=$?
          fi
          hasErr=$(jq -r 'if .stderr == null then "no" else "yes" end' <<<"$c")
          expErr=$(jq -r '.stderr // ""' <<<"$c")
          ok=1
          [ "$code" = "$expStatus" ] || ok=0
          if [ "$hasOut" = yes ] && [ "$actual" != "$expOut" ]; then ok=0; fi
          if [ "$hasErr" = yes ] && [ -z "$expErr" ] && [ -s "$errf" ]; then ok=0; fi
          [[ "$(<"$errf")" == *"$expErr"* ]] || ok=0
          if [ "$ok" = 1 ]; then
            report+="  ✅ $name"$'\n'
          else
            report+="  ❌ $name (exit $code, got: $actual, stderr: $(<"$errf"))"$'\n'
            fail=1
          fi
        done < <(jq -c '.[]' <<<"$casesJson")

        for args in "" option browse; do
          total=$((total + 1))
          name="argument-aliases: lets --help $args"
          # shellcheck disable=SC2086
          actual=$(${aliasesHelp} $args 2>&1) || true
          # shellcheck disable=SC2016
          case $actual in
          *'from $LETS_ALIAS_URL'* | *'printed with `printf`'*)
            report+="  ✅ ''${name% }"$'\n'
            ;;
          *)
            report+="  ❌ ''${name% } (got: $actual)"$'\n'
            fail=1
            ;;
          esac
        done

        if [ "$fail" = 0 ]; then
          report+="✅ $total example case(s) passed"$'\n'
          printf '%s' "$report" >"$out"
        else
          printf '%s' "$report" >&2
          echo "❌ example assertions failed" >&2
          exit 1
        fi
      '';
  completions =
    let
      fixtureLets = import ../tests/fixture-lets.nix { inherit pkgs; };
      L = "${fixtureLets}/bin/lets";
      plainPatternLets = import ../lib/mkLets.nix {
        inherit pkgs;
        inherit (import ../tests/fixture.nix { inherit pkgs; }) tasks;
      };
      dirPatternLets = import ../lib/mkLets.nix {
        inherit pkgs;
        inherit (import ../tests/fixture.nix { inherit pkgs; }) tasks;
        secrets = {
          command = "true {}";
          pattern = "secrets/{name}.yaml";
        };
      };
    in
    pkgs.runCommand "check-completions"
      {
        nativeBuildInputs = [
          pkgs.bashInteractive
          pkgs.zsh
          pkgs.fish
          pkgs.nushell
        ];
      }
      ''
        export HOME="$TMPDIR"
        fail=0

        echo "wrapper"
        (mkdir "$TMPDIR/wrapper" && cd "$TMPDIR/wrapper" &&
          bash ${../tests/wrapper.sh} ${L}) || fail=1
        echo "bash"
        bash ${../tests/bash-complete.sh} ${L} ${../completions/lets.bash} || fail=1
        echo "zsh"
        zsh ${../tests/zsh-complete.zsh} ${L} ${../completions/lets.zsh} || fail=1
        echo "fish"
        fish ${../tests/fish-complete.fish} ${L} ${../completions/lets.fish} || fail=1
        echo "nushell"
        bash ${../tests/nu-complete.sh} ${L} ${../completions/lets.nu} || fail=1
        echo "secret names"
        touch "$TMPDIR/flake.nix" "$TMPDIR/dev"
        if [ -n "$(cd "$TMPDIR" && ${plainPatternLets}/bin/lets __complete lets -S "")" ]; then
          echo "  ❌ lets -S <TAB> offers nothing when pattern is {name}"
          fail=1
        else
          echo "  ✅ lets -S <TAB> offers nothing when pattern is {name}"
        fi
        mkdir "$TMPDIR/secrets"
        touch "$TMPDIR/secrets/ci.yaml" "$TMPDIR/secrets/other.txt"
        got="$(cd "$TMPDIR" && ${dirPatternLets}/bin/lets __complete lets -S "")"
        if [ "$got" = ci ]; then
          echo "  ✅ lets -S <TAB> strips a directory in the pattern"
        else
          echo "  ❌ lets -S <TAB> strips a directory in the pattern (got: $got)"
          fail=1
        fi

        if [ "$fail" = 0 ]; then
          touch "$out"
        else
          echo "❌ completion assertions failed" >&2
          exit 1
        fi
      '';
}
