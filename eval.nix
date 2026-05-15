let
  flake = builtins.getFlake (toString ./.);
  system = flake.nixosConfigurations.orin-nano;
in
system.config.containers.ollama.config.services.ollama.package.outPath
