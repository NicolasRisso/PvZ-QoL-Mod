# Code signing and distribution trust

## The thing to understand first

Signing solves **one** problem: the SmartScreen "Windows protected your PC -
unknown publisher" dialog.

It does **not** stop antivirus flagging this tool. Its whole job is
`OpenProcess` + `WriteProcessMemory` on another process plus synthesised input.
That is the exact behaviour signature of a game trainer, because it *is* one.
Several engines classify that as HackTool or Riskware **by design**, and a valid
signature does not change the verdict - it only tells the user who signed it.

So expect to keep the "some antivirus may flag this" note in the README even
after signing. Anyone promising otherwise is selling certificates.

## What does not work

**A self-signed certificate is worthless here.** Windows does not trust it, so
the SmartScreen warning stays exactly as it is. It can look worse than shipping
unsigned, because it reads as an attempt to appear trustworthy. Don't.

## Options that do work

### Azure Trusted Signing - recommended

Microsoft's managed signing service. Roughly **$10/month**, which is an order of
magnitude below traditional certificates, and it is the only realistic option
for an individual now that private keys must live on certified hardware.

- Individual identity validation is supported, not just registered companies.
- Certificates are short-lived and issued per signing operation; there is no USB
  token to keep track of.
- Integrates directly with GitHub Actions - the workflow in
  `.github/workflows/build.yml` already has the step, gated on secrets so builds
  keep working until it is set up.

Requirements: an Azure subscription, identity validation (individuals generally
need a verifiable history - check current requirements, they have moved), and a
Trusted Signing account plus certificate profile.

Secrets to add to the repository:

```
AZURE_TENANT_ID
AZURE_CLIENT_ID
AZURE_CLIENT_SECRET
AZURE_ENDPOINT              e.g. https://eus.codesigning.azure.net
AZURE_CODE_SIGNING_NAME
AZURE_CERT_PROFILE_NAME
```

The signing step is skipped automatically when `AZURE_CLIENT_ID` is absent, so
forks and unsigned local builds still succeed.

### OV certificate

A traditional Organization Validation cert from a public CA, roughly
**$200-400/year**. Since 2023 the private key must sit on FIPS 140-2 Level 2
hardware, so it arrives as a USB token or a cloud HSM - which makes CI signing
awkward.

Important: an OV certificate does **not** clear SmartScreen immediately. It
builds reputation over time, so early downloaders still see the warning.

### EV certificate

**$300-600/year**, hardware token required, normally needs a registered business
entity. The one thing it buys that OV does not is *immediate* SmartScreen
reputation. Overkill for a game mod unless you are already signing other things.

## Free measures, already implemented

These are worth more than a signature to the audience that downloads game mods
off GitHub, and they cost nothing:

- **Build provenance attestation** (`actions/attest-build-provenance`) on tagged
  releases. Produces a cryptographically verifiable statement that the exe came
  from this repository and this workflow. Anyone can check it:

  ```
  gh attestation verify pvz-speed.exe --repo <owner>/<repo>
  ```

- **SHA256SUMS.txt** published with every release and every CI artifact, so a
  download can be checked against the build.

- **Built in public CI from public source.** The binary is never produced on a
  developer machine, so there is no step a reader cannot inspect.

## If Defender flags it anyway

Submit it as a false positive - Microsoft processes these and it fixes the
detection for everyone, not just you:

<https://www.microsoft.com/en-us/wdsi/filesubmission>

Attach the release URL and point at the source. A signed binary makes this
process go faster, which is a real if indirect benefit of signing.

## Recommendation

1. Ship now, unsigned, with the checksum and provenance already in place, and be
   upfront in the README about what the tool does and why AV may complain.
2. If downloads pick up and the warnings become a real barrier, add Azure
   Trusted Signing - it is ~$10/month and the workflow step is already written.
3. Skip EV unless a business entity already exists.
