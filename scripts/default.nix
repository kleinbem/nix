{ pkgs, ... }:

let
  python = pkgs.python3.withPackages (
    ps: with ps; [
      mcp
      pydantic
      pydantic-core
      psutil
      requests
      authlib
      cryptography
      google-api-python-client
      google-auth-httplib2
      google-auth-oauthlib
    ]
  );
in
pkgs.writeShellApplication {
  name = "atlas";

  runtimeInputs = [
    python
    pkgs.nix
    pkgs.sops
    pkgs.systemd
  ];

  text = ''
    # Find the script location relative to this tool
    # In a real flake we would copy the source, but for this dev setup 
    # we point to your live scripts folder for easy editing.
    PYTHON_SCRIPT="/home/martin/Develop/github.com/kleinbem/nix/scripts/workspace-mcp.py"

    # Run the atlas logic with the bundled python environment
    exec python3 "$PYTHON_SCRIPT" "$@"
  '';
}
