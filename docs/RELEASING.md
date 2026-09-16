# Releasing

One-time setup, then `./scripts/release.sh <version>` does everything else.

## Why notarization matters

An app downloaded from the internet carries a quarantine flag. If it is not
signed with a **Developer ID Application** certificate *and* notarized by
Apple, Gatekeeper refuses to open it:

```
$ spctl -a -vvv -t exec "Automatic Mouse Mover.app"
Automatic Mouse Mover.app: rejected
```

On macOS 26+ the old right-click → Open workaround no longer exists. A user
would have to go to System Settings → Privacy & Security and click "Open
Anyway" — which most people won't do for a tool that moves their cursor, and
reasonably so.

Notarizing removes that friction entirely: the app opens on first double-click
with no warning.

## One-time setup

Both steps involve a private key and an Apple ID password, so they must be done
by the account holder.

### 1. Create a Developer ID Application certificate

This requires a **paid** Apple Developer membership ($99/year). Free accounts
can only create "Apple Development" certificates, which cannot notarize.

**a. Generate a Certificate Signing Request on this Mac.**

Open Keychain Access → menu **Certificate Assistant** → **Request a Certificate
From a Certificate Authority…**

- User Email Address: your Apple ID email
- Common Name: your name
- Select **Saved to disk**
- Save as `CertificateSigningRequest.certSigningRequest`

This generates a private key in your login keychain. That key never leaves your
Mac, and it is what makes the resulting certificate yours.

**b. Create the certificate.**

Go to <https://developer.apple.com/account/resources/certificates/add>, choose
**Developer ID Application**, upload the CSR from the previous step, then
download the resulting `.cer` file.

**c. Install it.** Double-click the downloaded `.cer`. Confirm it landed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see one line. If you see nothing, the certificate did not install
into the login keychain.

### 2. Store notarization credentials

Notarization authenticates with an **app-specific password**, not your Apple ID
password.

**a.** Create one at <https://account.apple.com> → Sign-In and Security →
App-Specific Passwords. Name it something like "notarytool".

**b.** Find your Team ID (the 10-character code) at
<https://developer.apple.com/account> under Membership details, or from:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

It is the value in parentheses.

**c.** Store the credentials in the keychain under the profile name `AMM`:

```bash
xcrun notarytool store-credentials "AMM" \
    --apple-id "saulfm08@gmail.com" \
    --team-id "B3CW6K4QQ3" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

## Cutting a release

```bash
./scripts/release.sh 2.0.0
```

The script refuses to run if either prerequisite is missing, rather than
producing an artifact that would be rejected on every downloader's Mac. When it
succeeds it prints the Gatekeeper verdict, which should read `accepted`.

Artifacts land in `dist/`:

- `AutomaticMouseMover-<version>.zip`
- `AutomaticMouseMover-<version>.dmg`

Then publish them:

```bash
gh release create v2.0.0 \
    dist/AutomaticMouseMover-2.0.0.zip \
    dist/AutomaticMouseMover-2.0.0.dmg \
    --title "v2.0.0" \
    --notes-file docs/release-notes-2.0.0.md
```

## Verifying a release before publishing

Confirm the artifact will actually open on someone else's Mac:

```bash
# Should print: accepted / source=Notarized Developer ID
spctl -a -vvv -t exec "dist/Automatic Mouse Mover.app"

# Should print: The validate action worked!
xcrun stapler validate "dist/Automatic Mouse Mover.app"
```

Stapling matters: it embeds the notarization ticket in the bundle so it
validates even when the user is offline.
