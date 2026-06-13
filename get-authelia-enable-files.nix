let
  flake = builtins.getFlake (toString ./.);
  host = flake.nixosConfigurations.nixos-nvme;
in
host.options.my.containers.authelia.enable.files
