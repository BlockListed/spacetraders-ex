{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
        flake-utils.url = "github:numtide/flake-utils";
    };
    outputs = {self, nixpkgs, flake-utils}:
        flake-utils.lib.eachDefaultSystem (system:
            let
                pkgs = nixpkgs.legacyPackages.${system};
            in
            {
                devShells.default = pkgs.mkShellNoCC {
                    packages = [ pkgs.elixir_1_18 pkgs.elixir-ls pkgs.git ];

                    # needed for tmux
                    shellHook = ''
                        export SHELL=${pkgs.bashInteractive}/bin/bash
                    '';
                };
            }
        );
}
