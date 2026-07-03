with import <nixpkgs> { system = "aarch64-linux"; };
runCommand "test-strace" {
  nativeBuildInputs = [ strace ];
} ''
  strace -f -o $out /nix/store/rprpkkhvvf36qgpxhdjb7nmq26ayhf3f-bash-interactive-5.3p9/bin/bash -c "echo hello"
''
