{ pkgs }:
{
  unit =
    pkgs.runCommand "check-unit"
      {
        failuresJson = builtins.toJSON (
          pkgs.lib.runTests (import ../tests/args.nix { inherit pkgs; })
          ++ pkgs.lib.runTests (import ../tests/validate.nix { inherit pkgs; })
          ++ pkgs.lib.runTests (import ../tests/mkTask.nix { inherit pkgs; })
          ++ pkgs.lib.runTests (import ../tests/mkCompletions.nix { inherit pkgs; })
          ++ pkgs.lib.runTests (import ../tests/render.nix { inherit pkgs; })
        );
      }
      ''
        if [ "$failuresJson" = "[]" ]; then
          echo "✅ unit tests passed"
          touch "$out"
        else
          echo "❌ unit test failures:" >&2
          printf '%s\n' "$failuresJson" >&2
          exit 1
        fi
      '';
  examples =
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
          if actual=$(env "''${unsetargs[@]}" "''${envv[@]}" "$bin" "''${argv[@]}" 2>/dev/null); then
            code=0
          else
            code=$?
          fi
          ok=1
          [ "$code" = "$expStatus" ] || ok=0
          if [ "$hasOut" = yes ] && [ "$actual" != "$expOut" ]; then ok=0; fi
          if [ "$ok" = 1 ]; then
            report+="  ✅ $name"$'\n'
          else
            report+="  ❌ $name (exit $code, got: $actual)"$'\n'
            fail=1
          fi
        done < <(jq -c '.[]' <<<"$casesJson")

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

        echo "bash"
        bash ${../tests/bash-complete.sh} ${L} ${../completions/lets.bash} || fail=1
        echo "zsh"
        zsh ${../tests/zsh-complete.zsh} ${L} ${../completions/lets.zsh} || fail=1
        echo "fish"
        fish ${../tests/fish-complete.fish} ${L} ${../completions/lets.fish} || fail=1
        echo "nushell"
        bash ${../tests/nu-complete.sh} ${L} ${../completions/lets.nu} || fail=1

        if [ "$fail" = 0 ]; then
          touch "$out"
        else
          echo "❌ completion assertions failed" >&2
          exit 1
        fi
      '';
}
