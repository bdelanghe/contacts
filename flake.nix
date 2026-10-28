{
  description = "contacts: a local vCard store (vdir) and a loopback-only Radicale CardDAV server in front of it, as a Home Manager module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Only for the module-eval check; consumers already carry home-manager and should `follows` it.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      homeManagerModules.default = import ./nix/module.nix;

      checks = forAll (pkgs: lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        # Under Home Manager: nothing by default; on, Radicale bound to loopback only, storing into the vdir, and the vdir created at activation.
        module-eval =
          let
            hm = extra: (home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [ self.homeManagerModules.default { home = { username = "t"; homeDirectory = "/Users/t"; stateVersion = "24.11"; }; } extra ];
            }).config;
            on = hm { programs.contacts = { enable = true; port = 5299; }; };
            off = hm { };
            args = on.launchd.agents.radicale.config.ProgramArguments;
          in
          assert !(off.launchd.agents ? radicale && off.launchd.agents.radicale.enable) && !(off.home.activation ? contactsVdir);
          assert on.launchd.agents.radicale.config.KeepAlive == true;
          assert lib.hasInfix "/Users/t/.local/share/contacts" on.home.activation.contactsVdir.data;
          pkgs.runCommand "contacts-module-eval" { } ''
            grep -qx 'hosts = 127.0.0.1:5299' ${builtins.elemAt args 2}
            grep -qx 'filesystem_folder = /Users/t/.local/share/contacts' ${builtins.elemAt args 2}
            grep -qx 'type = none' ${builtins.elemAt args 2}
            [ "$(grep -c '^hosts = ' ${builtins.elemAt args 2})" = 1 ] && ! grep -q '0\.0\.0\.0\|::' ${builtins.elemAt args 2}
            touch $out
          '';
      } // {
        # Radicale starts on the rendered config shape and answers on loopback (any system with radicale).
        radicale-serves = pkgs.runCommand "contacts-radicale-serves" { nativeBuildInputs = [ pkgs.radicale pkgs.curl ]; } ''
          mkdir -p vdir
          printf '[server]\nhosts = 127.0.0.1:5233\n[auth]\ntype = none\n[storage]\nfilesystem_folder = %s\n[logging]\nlevel = warning\n' "$PWD/vdir" > conf
          radicale --config conf & pid=$!
          for i in $(seq 1 50); do curl -sf -o /dev/null http://127.0.0.1:5233/.web/ && break; sleep 0.2; done
          curl -sf -o /dev/null http://127.0.0.1:5233/.web/
          kill $pid
          touch $out
        '';
      });
    };
}
