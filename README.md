# contacts

A local vCard store and a CardDAV server in front of it, as a Home Manager module (launchd, macOS).

- **The vdir** (`programs.contacts.vdir`, default `~/.local/share/contacts`): a directory of `.vcf` files (RFC 6350).
  Anything that ingests contacts reads it directly: no server, API or credential.
- **Radicale** on `127.0.0.1:<port>` (default 5232), storing into that same directory, so Contacts.app or a phone
  can write cards over CardDAV. Loopback only, so no auth; if it ever binds anything else it needs auth first.
- `vdirsyncer` is installed, not wired: pulling an existing address book in is left to you.

```nix
inputs.contacts = { url = "github:bdelanghe/contacts"; inputs.nixpkgs.follows = "nixpkgs"; inputs.home-manager.follows = "home-manager"; };
# modules = [ contacts.homeManagerModules.default ];
programs.contacts.enable = true;
```

## Checks

`nix flake check`: Radicale serves on loopback with the module's config shape; on macOS the module under Home Manager.
