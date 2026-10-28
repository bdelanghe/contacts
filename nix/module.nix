{ config, lib, pkgs, ... }:

# Contacts as a local vCard store, and a CardDAV server in front of it.
#
# An ingester (e.g. a knowledge-graph importer) reads a VDIR — a directory of `.vcf` files, RFC 6350. That
# is the whole requirement for ingestion: no server, no API, no credential.
# This creates the directory, so an ingester has something to read the moment
# a card lands there.
#
# THE SERVER IS FOR THE HUMAN, NOT FOR FACTO. Radicale is here because a
# directory nothing writes to stays empty, and the realistic writers are
# Contacts.app and a phone — both of which speak CardDAV and neither of which
# will drop files into a folder. Ingesters read the vdir underneath either way,
# so if Radicale is ever removed the ingester keeps working.
#
# ── Why a local server rather than Google Contacts ──
#
# Google is the obvious alternative. The reasons against it: an ingester that
# reads something on disk needs no OAuth dependency, and contacts would be the
# only source whose data leaves and returns.
# It would also put contacts — the most identifying corpus in the graph after
# login IPs — behind a token that expires, in a service whose export is a
# one-shot link. A vdir is a directory you can `rm`.
#
# ── What this does NOT do ──
#
# It does not seed the vdir. Contacts.app is TCC-protected, and exporting from
# Google needs a consent only the user can give. Bootstrapping
# is one export away and is deliberately left as a human act — the same line
# drawn at every OAuth flow in this tree.

let
  cfg = config.programs.contacts;
  # The vdir ingesters read (default ~/.local/share/contacts). Not under
  # xdg.stateHome: state is what a program regenerates, and an address book is
  # the opposite — it is the only copy, and it belongs where a human expects to
  # find and back up data.
  vdir = cfg.vdir;

  stateDir = "${config.xdg.stateHome}/radicale";

  # LOOPBACK ONLY, and unauthenticated because of it. Radicale's own auth is
  # a htpasswd file, which on a single-user machine is a password protecting
  # data from the person who already owns the filesystem. Binding to 127.0.0.1
  # is the real control: nothing off this machine can reach it, and adding a
  # password would suggest a boundary that the bind already enforces better.
  #
  # If this ever binds anything but loopback, it needs auth before it does.
  port = cfg.port;

  config' = pkgs.writeText "radicale.conf" ''
    [server]
    hosts = 127.0.0.1:${toString port}

    [auth]
    type = none

    [storage]
    # PLAIN FILES, not a database. This is the whole point: the storage layer
    # IS the vdir that contacts-facto reads, so there is no export step and no
    # second copy to drift. Radicale writes `.vcf` here and facto reads the
    # same bytes.
    filesystem_folder = ${vdir}

    [logging]
    level = warning
  '';
in
{
  options.programs.contacts = {
    enable = lib.mkEnableOption "a local vCard store (vdir) and a loopback-only Radicale CardDAV server in front of it";
    vdir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/contacts";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.local/share/contacts"'';
      description = "The directory of .vcf files (RFC 6350 vdir) Radicale stores into and ingesters read.";
    };
    port = lib.mkOption { type = lib.types.port; default = 5232; description = "Loopback port Radicale listens on (127.0.0.1 only; no auth, see the module header)."; };
  };

  config = lib.mkIf cfg.enable {
    # The vdir exists whether or not Radicale ever runs. An ingester
    # depends on the DIRECTORY, not the server, and creating it here is what
    # turns its skip from "no vdir" into "no .vcf files" — a different and more
    # honest report of the same emptiness.
    home.activation.contactsVdir =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg vdir}
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
      '';

    launchd.agents.radicale = {
      enable = true;
      # Safe: KeepAlive brings it back if a boot race loses the first start, so
      # the wait4path guard buys nothing and costs a Login Items row reading `sh`.
      waitForNixStore = false;
      config = {
        ProgramArguments = [
          "${pkgs.radicale}/bin/radicale"
          "--config"
          "${config'}"
        ];
        # Resident: a CardDAV server that is not listening is not a server.
        RunAtLoad = true;
        KeepAlive = true;
        # Bounds a crash loop — a bad config would otherwise respawn as fast as
        # launchd can fork.
        ThrottleInterval = 30;
        StandardOutPath = "${stateDir}/radicale.log";
        StandardErrorPath = "${stateDir}/radicale.log";
      };
    };

    # `vdirsyncer` is NOT wired to anything, and is here as the tool for the one
    # job this module deliberately leaves undone: pulling an existing address
    # book in. Declaring a sync target would mean choosing a remote and storing
    # its credential, which is the decision this module exists to avoid making
    # on the user's behalf.
    home.packages = [ pkgs.vdirsyncer ];
  };
}
