# Operational certificate chain validation

Follow-up folded into the `refactor/cleanup` PR at the user's request (2026-09-12). The gap is recorded
in `tasks/todo.md`: the device verifies that a CASE peer holds the private key of the certificate it
presents, but never that the certificate was issued by the fabric's root, and `AddNOC` checks format
only. A fabric member who knows the IPK can therefore mint a certificate naming any node id or CAT.

## Why this needs a DER encoder

A Matter operational certificate travels as TLV, but its signature is computed over the ASN.1 DER form
of the certificate without the signature (matter.js `X509Base#asUnsignedAsn1`, `kinds/X509Base.ts`).
Verifying one means converting TLV to DER byte-exactly. The refactor removed the X.509 helpers, and
`Codec::DERCodec` is limited to the certification declaration encoder.

## Step 1: DER primitives

`Codec::DERCodec::Base` gains the encoders certificates need and the CD encoder does not: boolean,
bit string with an unused-bit count, integer from raw bytes, UTF8String / PrintableString / IA5String,
UTCTime and GeneralizedTime, explicit and implicit context tags, and sequence/set over already encoded
members. `encode_ansi1` and `encode_length_bytes` become the shared primitives rather than private.

## Step 2: TLV to DER

`Crypto::MatterCertificate.to_unsigned_asn1(cert_tlv : Bytes) : Bytes` walks the parsed `TLV::Any` in
**wire order**, because the DN is a tagged list whose order the issuer signed over, and emits:

    SEQUENCE {
      [0] INTEGER 2, INTEGER serial, SEQUENCE { OID ecdsa-with-SHA256 },
      issuer DN, SEQUENCE { notBefore, notAfter }, subject DN,
      SEQUENCE { SEQUENCE { OID ecPublicKey, OID prime256v1 }, BIT STRING key },
      [3] SEQUENCE { extensions }
    }

A DN attribute is `SET { SEQUENCE { OID, value } }`; Matter attributes (node id, fabric id, ICAC id,
RCAC id, CAT) are 16-character upper-case hex strings under `1.3.6.1.4.1.37244.1.*`, and a repeated
CAT field expands in place. Extensions are basic constraints, key usage, extended key usage, subject
key identifier, authority key identifier and raw future extensions, each critical where the spec says.

Gate: the matter.js `CERTIFICATE_SETS` vectors (chip test certs, the Matter 1.2 specification certs and
Apple's) carry TLV and its expected ASN.1 side by side. Every one must reproduce byte for byte.

## Step 3: verification

`Crypto::MatterCertificate.verify_signature(cert_tlv, issuer_public_key)` is SHA-256 ECDSA over the
step 2 output with the raw r‖s signature from tag 11. `verify_chain(noc, icac, root_public_key)`
verifies the NOC against the ICAC's public key when an ICAC is present and the ICAC against the root,
otherwise the NOC against the root, and checks that each issuer is a CA with the matching subject key
identifier.

## Step 4: enforcement

- CASE Sigma3 (`Session::Case::CaseResponder`): the peer NOC and its optional ICAC must chain to the
  fabric's `root_public_key`. The fabric is already pinned by Sigma1's destination id.
- `AddNOC` / `UpdateNOC` (`Commissioning::CredentialService`): the NOC must chain to the trusted root
  added in the same failsafe, answering `InvalidNoc` when it does not.

## Step 5: the in-repo controller becomes a real CA

`Controller::Commissioning::Commissioner` issues its root, ICAC and NOC with a random 64-byte
signature, so enforcing step 4 would break `examples/run_validation.sh`. It signs them properly: the
root self-signed with its own key, the NOC under it, with the subject and authority key identifiers
derived from the public keys.

## Verification

| Gate | When |
|---|---|
| golden TLV to ASN.1 vectors byte-exact | Step 2 |
| chain accepted for a real fixture chain, rejected for a forged NOC | Step 3 |
| `crystal spec`, format, ameba | every step |
| `./test` (chip-tool commissions, restarts, multi-fabric) and `run_validation.sh` 20/20 | Steps 4 and 5 |
