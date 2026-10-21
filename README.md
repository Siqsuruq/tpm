# TPM - Tcl Package Manager (Client)

TPM is a cross-platform command-line utility to download and install packages from the Tcl Public Repository.

> **TPM is written entirely in Tcl using the NX object system and requires no external binaries.**

---

## 📦 Features

- List locally installed packages
- Fetch package index from a remote repository
- Check installed packages for available updates (`updates`)
- Install packages from remote
- Automatically installs to a writable path in `$auto_path`
- Works on Windows, Linux, macOS
- No `curl`, no `unzip` — pure Tcl (uses `http`, `zipfile::decode`)

---

## 🛠 Requirements

- Tcl 8.6+
- [NX](https://github.com/nm-wu/nsf), aka [The NextScripting Framework](https://next-scripting.org/xowiki/getstart)
- [tls 2.0b1](https://github.com/bohagan1/TclTLS/releases/tag/tls-2.0b1)
- [Tcllib](https://core.tcl-lang.org/tcllib) (for `zipfile::decode`, `http`, `json`, )

> You can check your version by running:  
> `tclsh` → `puts $tcl_version`

---

## 🚀 How to Use

1. **Clone this repo** or download it

```bash
git clone https://github.com/Siqsuruq/tclrepo
cd tpm
```

2. Run the TPM shell:

```bash
tclsh main.tcl
```

3. Use interactive commands:

```bash
> help
> installed
> installed nats jsonlib
> available
> updates
> install nats
> update nats
> delete nats
> exit
```

`installed` shows an **Origin** column: `tpm` for packages recorded in TPM's
installation manifests, and `system` for packages discovered without a manifest.
Manifests are saved in `var/installed/*.tpm` and survive restarts. Packages
installed before manifest tracking are treated as system packages too.

System packages require `--force` (or `-f`) for deletion or installation of a
repository version:

```text
delete json --force
delete itcl --version 4.3.8
delete itcl --all --force
update json -f
install json --force
```

When multiple installations exist, `delete <package>` lists their versions,
origins, and paths, then asks for an installation number or `all`. Press Enter
to cancel. Use `--version <version>` to delete that version directly, or `--all`
to delete every version. System installations still require `-f` / `--force`;
force alone does not select all versions. If the same version is installed in
multiple locations, `--version` selects all matching locations; the numbered
prompt lets you choose one location.

`update <package>` installs only when the repository has a newer version;
`install <package>` skips packages already installed; use `--force` to reinstall
or `update` to check for a newer version. New installations select the latest
repository version. An update installs
into TPM's configured installation directory and can coexist with an older
system version. Tcl's runtime files, TPM's private dependencies, and package
search roots remain protected even with force.

Repository listings use `/api/v2/packages/list_platform_packages?platform=...`,
with the platform value returned by Tcl's `platform::generic` (for example,
`linux-x86_64`). Available packages, installs, updates, and dependency resolution
all use this platform-specific index.

Before installing, TPM stages the requested package and checks `package require`
in a fresh process using the current Tcl executable. Missing dependencies are
downloaded recursively, selecting versions compatible with the requested Tcl
version requirement (including `-exact`). Existing loadable dependencies are
reused. TPM validates the staged packages before copying them into the install
directory and records every downloaded dependency in its own manifest.
The probe loads the version registered by the target archive. If that differs
from the repository's version, TPM reports the mismatch and retains the
original metadata as `repository_version` in the manifest.

Probes have a 30-second timeout. Missing repository dependencies, cycles,
conflicting versions, and other package loading errors stop installation.
When a loader catches missing-package errors and names those packages in its
final error (for example, `twapi` or `cffi` on Windows), TPM tries an available
candidate and probes again. This is inferred from the diagnostic and the
recorded require calls; unrelated optional missing packages are ignored.
Repository package names must match their Tcl package registrations; TPM does
not infer which differently named distribution provides a missing package.

Repository package records may optionally include a `dependencies` list of
dictionaries with `name`, optional `version`, and optional boolean `exact`:

```tcl
dependencies {{name json version 1.3} {name example version 2.0 exact 1}}
```

The subprocess check executes package code; it is not a security sandbox.
Dependencies loaded only when particular functions are called require explicit
metadata, since `package require` cannot discover them.

## 💡 Example Output

```bash
> available
Fetching packages from remote...
 - nats                 3.1.1   (Tcl): Tcl client for NATS messaging
 - jsonlib              1.0.0   (Tcl): Fast JSON parser

> install nats
Downloading from: https://tclrepo.daidze.org/api/v2/download/package/abc-uuid
Installing to: /home/user/.local/lib/tpm
✓ Package 'nats' installed successfully

> installed nats
✓ nats                 version: 3.1.1
```

## 📂 Folder Structure
```bash
main.tcl            # Entry point
app.tcl             # CLI application logic
pkgdb.tcl           # Local/remote package metadata manager
installer.tcl       # Download + install logic
net.tcl             # HTTP client to fetch remote data
system.tcl          # System/environment info singleton
var/config          # Local configuration file
```

## 🐛 Found a Bug?

Open an issue or a pull request — contributions are welcome!

## 📜 License

MIT License. Free for personal or commercial use.
