{ pkgs, ... }:

let
  # Simple test to check if a binary exists in the path
  testBinary = bin: ''
    if ! command -v ${bin} &> /dev/null; then
      echo "❌ Test Failed: Binary '${bin}' not found."
      exit 1
    else
      echo "✅ Test Passed: Binary '${bin}' found."
    fi
  '';
in
pkgs.writeShellScriptBin "run-agent-tests" ''
  echo "🧪 Running Agent Integrity Tests..."

  # Check for Critical Tools
  ${testBinary "git"}
  ${testBinary "nix"}
  ${testBinary "rg"} # ripgrep (Antigravity favorite)

  # Check File Structure Integrity
  if [ ! -f "flake.nix" ]; then
    echo "❌ Critical: flake.nix missing!"
    exit 1
  fi

  echo "🎉 All Systems Nominal."
''
