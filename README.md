# get-powerbash

The installer served at [get.powerbash.org](https://get.powerbash.org).

```bash
curl -s https://get.powerbash.org | bash
```

To remove it again:

```bash
curl -s https://get.powerbash.org | bash -s -- uninstall
```

## What it does

* Downloads `powerbash.sh` from `https://download.powerbash.org/powerbash.sh`
  into `${XDG_DATA_HOME:-~/.local/share}/powerbash/`, and verifies it looks
  like powerbash before putting it in place.
* Links it into `~/.bashrc.d/` if that directory exists (Fedora/RHEL), and
  otherwise appends a marked block to `~/.bashrc` — or `~/.bash_profile` on
  macOS, where terminals start login shells.
* Re-running upgrades in place. Nothing is duplicated.
* Uninstalling removes exactly the marked block it added, leaving the rest of
  your startup file byte-for-byte as it was. Your saved settings in
  `~/.config/powerbashrc` are left alone.

**It refuses to run as root.** powerbash is a per-user tool; a multi-user
install is two manual commands and is documented — with its caveats — at
[powerbash.org/docs](https://powerbash.org/docs/#global).

## Environment

| Variable | Default |
|---|---|
| `POWERBASH_URL` | `https://download.powerbash.org/powerbash.sh` |
| `POWERBASH_INSTALL_DIR` | `${XDG_DATA_HOME:-~/.local/share}/powerbash` |

## Layout

`index.html` **is** the script. GitHub Pages serves it verbatim as the index
of `get.powerbash.org`, which is what makes `curl … | bash` work; `.nojekyll`
stops Pages from trying to process it.

## Tests

```bash
./tests/install-test.sh    # round trip against a throwaway $HOME, no network
./tests/test-bash32.sh     # the same suite under bash 3.2, in a container
```

Every case runs against a temporary `$HOME` and a `file://` URL, so the suite
never touches the machine running it.

## License

MIT — see [LICENSE](LICENSE).
