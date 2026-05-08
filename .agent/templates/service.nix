{ pkgs, ... }:

{
  # Import this module in your host config
  # imports = [ ../../modules/nixos/services/<name> ];

  # Basic systemd service example
  systemd.services."<service-name>" = {
    description = "<Description of service>";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hello}/bin/hello";
      Restart = "always";
      User = "root";
    };
  };
}
