# TLD Oracle v2 — Proposal Rationale

## What this proposal is asking the DAO to do

This proposal asks ENS DAO to deploy a smart contract called TLDMinter and authorize it as a controller of the ENS Root. Once authorized, TLDMinter allows ICANN-registered top-level domain operators to claim their TLD as an ENS name — trustlessly, on-chain, without requiring manual intervention from ENS Labs.

The mechanism: a TLD operator publishes a DNSSEC-signed TXT record at `_ens.nic.{tld}` pointing to their Ethereum address. TLDMinter reads that cryptographic proof on-chain via the existing DNSSECImpl oracle, verifies it, and if the TLD is on the DAO-approved allowlist, opens a 7-day claim window. The DAO or Security Council can veto during that window. If no veto, the TLD is assigned.

The initial allowlist covers 1,166 post-2012 ICANN gTLDs — the full set of generic TLDs delegated since the 2012 expansion round. Pre-2012 TLDs and `.eth` are explicitly excluded. `.eth` is permanently locked at the Root contract level — `Root.locked["eth"] = true` — meaning even if `.eth` were somehow added to the allowlist, any attempt by TLDMinter to call `setSubnodeOwner` for it would revert at the Root. The protection is enforced by the Root contract, not by TLDMinter itself.

---

## Proposal structure

Seeding 1,166 TLDs into the allowlist requires 1,166 SSTORE operations. Each SSTORE costs 20,000 gas. That's 23.3M gas at the floor, before deployment overhead.

The full proposal — deploying TLDMinter, authorizing it, and seeding all 1,166 TLDs — costs approximately 30.7M gas. Ethereum's block gas limit is currently 60M (raised from 30M in early 2025), so the entire proposal fits comfortably within a single block with ~48% headroom.

The proposal executes 6 calls through the DAO timelock:

1. **CREATE2 deploy** (~2.0M gas) — deploy TLDMinter at a deterministic address via the CREATE2 factory
2. **setController** (~25K gas) — authorize TLDMinter as a Root controller
3. **batchAddToAllowlist** (~7.4M gas) — seed TLDs 1–300
4. **batchAddToAllowlist** (~7.4M gas) — seed TLDs 301–600
5. **batchAddToAllowlist** (~7.4M gas) — seed TLDs 601–900
6. **batchAddToAllowlist** (~6.5M gas) — seed TLDs 901–1,166

Total governance time: ~9 days (one 7-day voting period + one 2-day timelock).

---

## Rate limiting

TLDMinter enforces a rate limit on claim execution: a maximum of 10 TLD claims per 7-day rolling window. This is set at deploy time via constructor arguments and is enforced in `submitClaim()`.

The DAO can adjust these parameters post-deployment via `setRateLimit()`, which is `onlyDAO`. The rate limit is a safety valve — it bounds the blast radius if a bad actor somehow obtained a valid DNSSEC proof for a non-intended TLD before the DAO could veto.

---

## Emergency pause

Both `pause()` and `unpause()` are gated by `onlyVetoAuthority` — accessible by the DAO Timelock or the Security Council Multisig while the SC is active. After the Security Council's mandate expires (July 24, 2026), only the DAO Timelock can pause or unpause TLDMinter. This is intentional: emergency response transitions from the SC to full DAO governance as the protocol matures.

---

## The Merkle root alternative

There is an alternative path worth noting for future reference.

Instead of writing 1,166 entries to storage, TLDMinter could store a single `bytes32` Merkle root at deploy time — a cryptographic commitment to the full 1,166-TLD set. When an operator submits a claim, they provide a Merkle proof that their TLD is in the approved set. TLDMinter verifies the proof on-chain in constant time and gas.

This would collapse the proposal to **2 calls**:
1. CREATE2 factory → deploy TLDMinter (with Merkle root committed in constructor)
2. Root → setController(tldMinter, true)

**The tradeoff:**

TLD operators submitting claims must provide a Merkle proof alongside their DNSSEC proof. This is a toolable, one-time step — but it is a UX change from the storage-based design, where the contract does the allowlist lookup internally. Future DAO additions to the allowlist would require a new Merkle root and a governance proposal to update it (vs. a simpler `addToAllowlist()` call under the current design).

Since the storage-based approach now fits in a single proposal, the Merkle root alternative is not necessary for this deployment. It remains a viable optimization for future iterations if the allowlist grows significantly.

---

## The question for delegates

The single-proposal structure is technically complete, fully tested, and ready to submit. All 1,166 TLDs are seeded in one governance cycle (~9 days), with no sequencing dependencies or follow-up proposals required.
