#!/usr/bin/env bash
#
# Builds Glassfin as a Flatpak.
#
# Two stages, and the split is deliberate — see the comment at the top of
# org.glassfin.Glassfin.yml. Stage one builds the Flutter application on the host;
# stage two builds libmpv inside the sandbox and copies stage one's output in.
#
#   ./linux/packaging/build-flatpak.sh           build and install for this user
#   ./linux/packaging/build-flatpak.sh --bundle  also write a single .flatpak file
#
# The first run takes a while: libplacebo and mpv are compiled from source.
# Afterwards flatpak-builder caches them and only the application is rebuilt.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
manifest="$here/org.glassfin.Glassfin.yml"
app_id="org.glassfin.Glassfin"

runtime_version="49"
build_dir="$root/build/flatpak"
state_dir="$root/build/flatpak-state"

bundle=false
[[ "${1:-}" == "--bundle" ]] && bundle=true

# Flutter is frequently not on PATH for a non-login shell.
if ! command -v flutter >/dev/null 2>&1 && [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi

missing=()
command -v flutter >/dev/null 2>&1 || missing+=("flutter (https://docs.flutter.dev/get-started/install/linux)")
command -v flatpak-builder >/dev/null 2>&1 || missing+=("flatpak-builder (pacman -S flatpak-builder)")

if ((${#missing[@]})); then
  printf 'Missing build tools:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

# The SDK is needed to compile the three libmpv modules; the Platform alone is
# only enough to run them.
for ref in "org.gnome.Platform/x86_64/$runtime_version" "org.gnome.Sdk/x86_64/$runtime_version"; do
  if ! flatpak info "$ref" >/dev/null 2>&1; then
    echo "Installing $ref…"
    flatpak install --assumeyes flathub "$ref"
  fi
done

echo "==> Building the Flutter application"
cd "$root"
flutter build linux --release

# Worth failing early and by name: the manifest copies this directory wholesale,
# and flatpak-builder's error for a missing source is considerably less obvious.
if [[ ! -x "$root/build/linux/x64/release/bundle/glassfin" ]]; then
  echo "flutter build produced no bundle at build/linux/x64/release/bundle" >&2
  exit 1
fi

echo "==> Building the Flatpak"
rm -rf "$build_dir"
flatpak-builder \
  --user \
  --install \
  --force-clean \
  --state-dir="$state_dir" \
  "$build_dir" \
  "$manifest"

if $bundle; then
  echo "==> Writing a single-file bundle"
  repo_dir="$root/build/flatpak-repo"
  flatpak-builder \
    --user \
    --force-clean \
    --state-dir="$state_dir" \
    --repo="$repo_dir" \
    "$build_dir" \
    "$manifest"
  flatpak build-bundle "$repo_dir" "$root/build/$app_id.flatpak" "$app_id"
  echo "Wrote build/$app_id.flatpak"
fi

cat <<EOF

Done. To run it:

    flatpak run $app_id

To add it to Steam as a non-Steam shortcut, point the shortcut at:

    /usr/bin/flatpak run $app_id

EOF
