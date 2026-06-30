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
    exec python3 -u ${./workspace-mcp.py} "$@"
  '';
}
