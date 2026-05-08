{
  pkgs,
  ...
}:

{
  imports = [
    # Core Home Manager & Secrets
    ./features/git.nix
    ./features/shell.nix
    ./features/starship.nix
  ];

  # Basic user info
  home = {
    username = "username";
    homeDirectory = "/home/username";

    # State Version (DO NOT CHANGE unless you know what you are doing)
    stateVersion = "24.11";

    # Packages
    packages = with pkgs; [
      # Core productivity
    ];
  };

  # Allow unfree packages for this user
  nixpkgs.config.allowUnfree = true;

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
