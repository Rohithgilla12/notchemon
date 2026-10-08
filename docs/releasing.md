# Releasing Notchemon

A release is a GitHub Release with three assets:

| Asset | Used by |
| --- | --- |
| `Notchemon-<version>.dmg` | People who download the app by hand. Drag the app onto the Applications link. |
| `Notchemon-<version>.zip` | Sparkle updates and the Homebrew cask. |
| `appcast.xml` | Sparkle. Installed apps read it from `https://github.com/Rohithgilla12/notchemon/releases/latest/download/appcast.xml`. |

Pushing a `v*` tag builds and publishes all three in CI. The app, the zip, and the DMG are signed with Developer ID and notarised. The zip in the appcast is signed with the Sparkle EdDSA key.

## Before the first release

Do these steps once. They need your Keychain, 1Password, and GitHub access, so run them yourself.

The commands use a 1Password vault named `Private`. If your vault has another name, change `Private` in each `op://` reference.

### Create the Sparkle signing key

1. Run the setup script:

	```sh
	scripts/setup-sparkle-keys.sh
	```

	It runs Sparkle's `generate_keys`, which stores the private key in your login Keychain under the account `notchemon`. The script writes the public key into `project.yml` as `SUPublicEDKey` and prints it. It never prints the private key. If a key already exists, the script reuses it.

2. Back up the private key to 1Password. If you lose it, installed copies of the app can never verify another update.

	```sh
	bin="$(scripts/sparkle-bin.sh)"
	backup="$(mktemp -d)/sparkle-private-key"
	"$bin/generate_keys" --account notchemon -x "$backup"
	op item create --vault Private --category "Secure Note" --title notchemon-sparkle "ed-private-key[file]=$backup"
	rm -P "$backup"
	```

3. Commit the change to `project.yml`.

Until `SUPublicEDKey` is set, the app never starts Sparkle and **Check for Updates…** stays disabled. The app also sets `SUVerifyUpdateBeforeExtraction`, so Sparkle checks the EdDSA signature before it unpacks an update. For a zip, that signature is required. Sparkle accepts a DMG or a package without it only when the archive itself carries a Developer ID signature from the same team.

### Store the signing credentials in 1Password

The release job needs a Developer ID certificate and an App Store Connect API key. Skip any item you already have.

1. Create a 1Password item with a generated password for the certificate export:

	```sh
	op item create --vault Private --category Password --title notchemon-developer-id --generate-password=32,letters,digits
	```

2. In Keychain Access, export **Developer ID Application: Rohith Gilla (7D2V3RM56T)** with its private key as `notchemon-developer-id.p12`. Paste the generated password from 1Password when Keychain Access asks for one.
3. Attach the `.p12` file to the item, then delete the file:

	```sh
	op item edit notchemon-developer-id --vault Private "certificate.p12[file]=$HOME/Downloads/notchemon-developer-id.p12"
	rm -P "$HOME/Downloads/notchemon-developer-id.p12"
	```

4. In App Store Connect, under **Users and Access › Integrations › App Store Connect API**, create a team key with the **Developer** role. Download the `.p8` file and note the key ID and the issuer ID.
5. Store the key in 1Password, then delete the file. Replace the placeholders with your key ID and issuer ID:

	```sh
	op item create --vault Private --category "Secure Note" --title notchemon-app-store-connect \
		"AuthKey.p8[file]=$HOME/Downloads/AuthKey_XXXXXXXXXX.p8" \
		"key-id[text]=XXXXXXXXXX" \
		"issuer-id[text]=00000000-0000-0000-0000-000000000000"
	rm -P "$HOME/Downloads/AuthKey_XXXXXXXXXX.p8"
	```

### Set the GitHub secrets

The release job reads six repository secrets. Each command pipes the value from 1Password into `gh`, so no secret reaches your shell history or the screen.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The Developer ID `.p12` file, base64-encoded. |
| `DEVELOPER_ID_P12_PASSWORD` | The password of that `.p12` file. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | The App Store Connect `.p8` key, base64-encoded. |
| `APP_STORE_CONNECT_KEY_ID` | The key ID of that API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID of your App Store Connect team. |
| `SPARKLE_ED_PRIVATE_KEY` | The exported Sparkle private key, as `generate_keys -x` wrote it. |

```sh
repo=Rohithgilla12/notchemon
op read -n "op://Private/notchemon-developer-id/certificate.p12" | base64 | gh secret set DEVELOPER_ID_P12_BASE64 -R "$repo"
op read -n "op://Private/notchemon-developer-id/password" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$repo"
op read -n "op://Private/notchemon-app-store-connect/AuthKey.p8" | base64 | gh secret set APP_STORE_CONNECT_API_KEY_BASE64 -R "$repo"
op read -n "op://Private/notchemon-app-store-connect/key-id" | gh secret set APP_STORE_CONNECT_KEY_ID -R "$repo"
op read -n "op://Private/notchemon-app-store-connect/issuer-id" | gh secret set APP_STORE_CONNECT_ISSUER_ID -R "$repo"
op read -n "op://Private/notchemon-sparkle/ed-private-key" | gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo"
gh secret list -R "$repo"
```

If any secret is missing, a tag push skips the release and the run names the missing secrets in a warning.

### Store notarisation credentials for local releases

CI notarises with the API key. To release from your Mac instead, store a `notarytool` profile named `notchemon` in your Keychain:

```sh
xcrun notarytool store-credentials notchemon --apple-id <your Apple ID> --team-id 7D2V3RM56T
```

`notarytool` prompts for an app-specific password. Create one at [account.apple.com](https://account.apple.com) under **Sign-In and Security › App-Specific Passwords**, and paste it at the prompt.

### Make the repository public

The repository is private. GitHub serves a private repository's release assets only to signed-in users with access, so:

- Installed apps get a 404 for `appcast.xml` and never see an update.
- `brew install --cask` cannot download the zip.
- The DMG link works only for you.

Make the repository public before you announce a release:

```sh
gh repo edit Rohithgilla12/notchemon --visibility public --accept-visibility-change-consequences
```

While the repository stays private, macOS runners also count against your Actions minutes at a higher rate than Linux runners. Public repositories run Actions for free.

## Release a version

1. List the changes under `## [Unreleased]` in `CHANGELOG.md`. The release notes, both on GitHub and in Sparkle's update window, come from this section.
2. Bump the version:

	```sh
	scripts/bump-version.sh 0.2.0
	```

	The script sets `CFBundleShortVersionString` to `0.2.0` and increments `CFBundleVersion` in `project.yml`. Sparkle compares `CFBundleVersion`, so every release needs a new build number. The script also moves the Unreleased notes under `## [0.2.0] - <today>`.
3. Review and commit the change, then tag and push:

	```sh
	git commit -am "chore(release): 0.2.0"
	git tag v0.2.0
	git push origin main v0.2.0
	```

4. Watch the run with `gh run watch`. The release job does the following:
	1. Checks that the tag matches the version in `project.yml` and that `SUPublicEDKey` is set.
	2. Runs `scripts/release.sh`, which archives, exports for Developer ID, verifies every signature, notarises and staples the app, and builds, signs, notarises, and staples the DMG.
	3. Runs `scripts/make-appcast.sh`, which signs the zip with the EdDSA key and embeds the CHANGELOG section as release notes.
	4. Creates the GitHub Release with the DMG, the zip, and `appcast.xml`.
	5. Commits the new version and `sha256` to `Casks/notchemon.rb` on `main`.

### Release from your Mac

Release from your Mac only while the release secrets are not set in GitHub. Otherwise the tag push also starts the CI release, and the two race to create the same release. Run these commands after you commit the version bump in step 3, instead of the `git tag` and `git push` commands:

```sh
scripts/release.sh
scripts/make-appcast.sh 0.2.0
git tag v0.2.0
git push origin main v0.2.0
gh release create v0.2.0 dist/Notchemon-0.2.0.dmg dist/Notchemon-0.2.0.zip dist/appcast.xml \
	--verify-tag --title "Notchemon 0.2.0" --notes "$(scripts/changelog-section.sh 0.2.0)"
scripts/update-cask.sh 0.2.0 "$(shasum -a 256 dist/Notchemon-0.2.0.zip | cut -d' ' -f1)"
```

`make-appcast.sh` reads the private key from your Keychain, so macOS may ask you to allow access. Commit and push the cask change.

## How the cask stays current

The release job commits the cask change straight to `main` instead of opening a pull request. The commit touches one file, and the job fetches `main` and retries if `main` moved during the release. A pull request would need the repository setting that lets Actions create pull requests, and checks do not run on a pull request that `GITHUB_TOKEN` opens, so it would wait for a manual merge anyway.

If you protect `main` against direct pushes, the step fails after the release is published. Run the `update-cask.sh` command that the error prints, and commit the change.

Because the cask lives in `Casks/` on `main`, this repository works as a tap:

```sh
brew tap Rohithgilla12/notchemon https://github.com/Rohithgilla12/notchemon
brew install --cask notchemon
```

The cask declares `auto_updates true`, so `brew upgrade` leaves updates to Sparkle.

## Things to know

- The first version that contains Sparkle cannot update itself into existence. People on 0.1.0 must install the next release by hand or with Homebrew. Automatic updates start from the release after that.
- Sparkle asks on the second launch whether to check for updates automatically. Until the person answers, **Check for Updates…** still works.
- Back up the Sparkle private key. A new key cannot sign updates for copies that shipped with the old public key.
- `scripts/test-scripts.sh` tests `bump-version.sh`, `changelog-section.sh`, and `update-cask.sh`. CI runs it on every push.
