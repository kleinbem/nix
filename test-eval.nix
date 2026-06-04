{
  pkgs ? import <nixpkgs> { },
}:
let
  eval = pkgs.lib.evalModules {
    modules = [
      (import (pkgs.path + "/nixos/modules/system/boot/initrd-ssh.nix"))
      {
        boot.initrd = {
          network.ssh = {
            enable = true;
            hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
          };
          secrets."/etc/ssh/ssh_host_ed25519_key" = pkgs.lib.mkForce "/nix/store/something";
        };
      }
    ];
  };
in
eval.config.boot.initrd.secrets
