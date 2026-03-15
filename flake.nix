{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    purescript-overlay = {
      url = "github:thomashoneyman/purescript-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dev-assets-mkdocs = {
      url = "github:paolino/dev-assets?dir=mkdocs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      purescript-overlay,
      dev-assets-mkdocs,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ purescript-overlay.overlays.default ];
          };
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [
              dev-assets-mkdocs.devShells.${system}.default
            ];
            buildInputs = [
              pkgs.purs
              pkgs.spago-unstable
              pkgs.purs-tidy-bin.purs-tidy-0_10_0
              pkgs.purescript-language-server
              pkgs.esbuild
              pkgs.nodejs_20
              pkgs.just
              pkgs.python3
              pkgs.playwright-test
            ];
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          };
        }
      );
    };
}
