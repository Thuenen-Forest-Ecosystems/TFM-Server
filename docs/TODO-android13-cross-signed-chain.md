# TODO (Admin): serve cross-signed HARICA chain for ci.thuenen.de

**Status:** open
**Priority:** high — Android 13 (and other older trust stores) cannot log in
**Owner:** whoever manages TLS termination for `ci.thuenen.de:443`
**Created:** 2026-06-25

---

## In plain words

**Is the chain broken? No.** The certificate chain is valid and complete. Modern
phones, computers, and browsers accept it without any problem.

**So what's wrong?** The certificate at the **top** of the chain
(`HARICA TLS RSA Root CA 2021`) is a fairly new one. **Old phones (Android 13 and
older) have never heard of it**, so they don't trust it and refuse to connect.
Newer devices were taught about it; old ones were not.

**Is something missing?** Yes — one helper certificate. The server is *not* sending
a "bridge" that lets old phones connect that top certificate to an **older, well-known**
certificate (`RootCA 2015`) that every old phone already trusts.

**The fix in one sentence:** Add that bridge — give the server a second copy of the top
certificate, the version that is signed by the old `RootCA 2015`. We already have this
file (`HARICA-TLS-Root-2021-RSA-cross.pem`); it just needs to be put into the chain the
server sends.

After that: modern devices keep working exactly as before, and old phones can finally
connect because they now have a trusted certificate to fall back on. Nothing is removed,
we only add the missing bridge.

---

## Problem

Users on **Android 13** get `certificate_verify_failed` when logging in to the TFM
app. macOS, Android 14+, and current desktop browsers are unaffected.

The certificate for `ci.thuenen.de` was renewed on **2026-06-24**. The CA chain did
**not** change — it is the same as before — but the renewal made the issue visible
to anyone whose session had to re-authenticate online.

The chain the server currently sends is:

```
0  CN=ci.thuenen.de                      (leaf)        issued by  GEANT TLS RSA 1
1  CN=GEANT TLS RSA 1                     (intermediate) issued by  HARICA TLS RSA Root CA 2021
2  CN=HARICA TLS RSA Root CA 2021         (root)        SELF-SIGNED
```

The chain terminates at the **self-signed** `HARICA TLS RSA Root CA 2021`. That root
was only added to the Android system trust store in **Android 14**. Android 13 and
older devices do not have it, so they cannot complete the path and reject the
connection.

> Note: This is the trust store used by the app's network layer (Flutter/`dart:io`).
> It does **not** read Android's `network_security_config.xml`, which is why the app's
> bundled GEANT trust anchor does not help here. See the app-side fix below.

## Fix: serve the cross-signed root instead of the self-signed root

HARICA publishes a **cross-signed** version of the 2021 root that is signed by the
older `Hellenic Academic and Research Institutions RootCA 2015`. That 2015 root has
been in Android trust stores for years (Android 7+), so swapping it in makes the
chain validate on old and new clients alike.

We already have the cross-signed cert in this directory:

- **`HARICA-TLS-Root-2021-RSA-cross.pem`**
  - subject: `CN=HARICA TLS RSA Root CA 2021`
  - issuer:  `CN=Hellenic Academic and Research Institutions RootCA 2015`
  - valid:   2021-09-02 → 2029-08-31

### What to change

Wherever TLS for `ci.thuenen.de` is terminated (the reverse proxy / Kong serving
`:443`), change the certificate chain file so the top of the chain is the
**cross-signed** 2021 root rather than the self-signed one.

Target chain (leaf first, root last):

```
1. <ci.thuenen.de leaf>
2. HARICA-GEANT-TLS-R1.pem               (CN=GEANT TLS RSA 1)
3. HARICA-TLS-Root-2021-RSA-cross.pem    (2021 root, cross-signed by RootCA 2015)
```

Do **not** also append the self-signed `HARICA-TLS-Root-2021-RSA.pem`. You do not need
to append `HaricaRootCA2015.pem` either — clients that need it already have it in their
trust store; sending it is just wasted bytes.

A ready-made full chain that already terminates at the 2015 root is also available in
this directory (`full-legacy-2015-harica-ca-chain-tls-*`); use it as a reference for
ordering. The only intermediate that matters for `ci.thuenen.de` is the GÉANT-branded
one (`GEANT TLS RSA 1` = `HARICA-GEANT-TLS-R1.pem`), since that is what signs our leaf.

### Why this is safe

- Clients that **have** the 2021 root (macOS, Android 14+, modern browsers) keep
  validating exactly as today — they stop at the trusted 2021 root and ignore the
  extra cross-cert.
- Clients that **lack** the 2021 root but **have** the 2015 root (Android 13, older
  devices) can now extend the path through the cross-cert to the 2015 root they trust.
- This is the same well-established pattern Let's Encrypt used with the cross-signed
  DST Root. It is additive, not a downgrade.

## Verification after deploying

```bash
# 1. Confirm the top of the served chain is now issued by RootCA 2015
echo | openssl s_client -connect ci.thuenen.de:443 -servername ci.thuenen.de -showcerts 2>/dev/null \
  | grep -E "s:|i:"
# Expect the last cert's issuer (i:) to be:
#   Hellenic Academic and Research Institutions RootCA 2015

# 2. Verification still passes
echo | openssl s_client -connect ci.thuenen.de:443 -servername ci.thuenen.de 2>&1 \
  | grep "Verify return code"
# Expect: Verify return code: 0 (ok)

# 3. Smoke-test login on a physical Android 13 device.
```

## Related app-side fix (already applied, separate deploy)

The Flutter app was also changed so it no longer depends on the device trust store at
all: it now loads the bundled HARICA CA into the `dart:io` `SecurityContext` on Android
(previously this workaround existed only for Windows). See
`TFM-app/lib/main.dart` (`_BundledCaHttpOverrides`) and
`TFM-app/assets/certs/ca-bundle.pem`.

- The **server-side** fix here unblocks **already-installed** app versions immediately,
  without an app update — users cannot update if they cannot log in, so this is the
  priority fix.
- The **app-side** fix ensures future builds never break again if a device trust store
  lags behind a CA migration.

Both should ship.
