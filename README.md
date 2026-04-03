# dao-proposals

Executable governance proposals for ENS DAO — calldata, contract snapshots, verification tests, and rationale documents. By estmcmxci.eth.

## Verify a proposal

```bash
cp .env.example .env
echo "MAINNET_RPC_URL=https://eth.drpc.org" >> .env
forge test --match-path "src/ens/proposals/<proposal-name>/*" --fork-url $MAINNET_RPC_URL -vv
```

CI runs automatically on PRs and pushes to main.

## Proposals

| Proposal | Status | Tests | Forum |
|----------|--------|-------|-------|
| [tld-oracle-v2](src/ens/proposals/tld-oracle-v2/) | Temp Check | 5 pass | [RFC](https://discuss.ens.domains/t/rfc-a-programmable-fast-path-for-tld-assignment/21859) |

## Structure

```
src/
├── ens/
│   ├── proposals/       # One directory per proposal (calldata, tests, rationale)
│   ├── Constants.sol     # Shared mainnet addresses
│   ├── ENS_Governance.sol # Governance lifecycle base contract
│   └── interfaces/       # IGovernor, ITimelock, IENSToken
├── base/                 # Reusable test utilities
└── dao-registry.json     # DAO metadata
```
