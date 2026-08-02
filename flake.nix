{
  description = "NixOS configuration";

  inputs = {
	nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

	home-manager = {
	    url = "github:nix-community/home-manager/release-26.05";
	    inputs.nixpkgs.follows = "nixpkgs";
	};

	noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
    ];

    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  outputs = { nixpkgs, home-manager, noctalia, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = {
        inherit noctalia;
      };

      modules = [
	  ./configuration.nix

	  home-manager.nixosModules.home-manager

	  {
	    home-manager.useGlobalPkgs = true;
	    home-manager.useUserPackages = true;

	    home-manager.users.nitesh = import ./home.nix;
	  }

	  noctalia.nixosModules.default
	];
    };
  };
}
