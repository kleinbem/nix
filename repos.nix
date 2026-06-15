# Sub-flake manifest for the meta-workspace.
#
# Replaces .gitmodules — meta no longer pins specific commits of each
# sub-flake. Deployment uses `--override-input <name> git+file://./<name>`
# (via OVERRIDES in .just/common.just) to read the LIVE local checkout.
#
# To clone all sub-flakes into the workspace, run `just jj::bootstrap`.
# Each sub-flake is its own independent repo with its own history & CI.
{
  nix-config = "git@github.com:kleinbem/nix-config.git";
  nix-devshells = "git@github.com:kleinbem/nix-devshells.git";
  nix-hardware = "git@github.com:kleinbem/nix-hardware.git";
  nix-packages = "git@github.com:kleinbem/nix-packages.git";
  nix-presets = "git@github.com:kleinbem/nix-presets.git";
  nix-secrets = "git@github.com:kleinbem/nix-secrets.git";
  nix-templates = "git@github.com:kleinbem/nix-templates.git";
}
