// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

interface ITLDMinter {
    function batchAddToAllowlist(string[] calldata tlds) external;
    function allowedTLDs(bytes32 labelHash) external view returns (bool);
    function version() external pure returns (string memory);
}

interface IRoot {
    function setController(address controller, bool enabled) external;
    function controllers(address controller) external view returns (bool);
}

/**
 * @title TLDOracleV2CalldataCheck
 * @notice Verifies the TLD Oracle v2 governance proposal executes the expected outcome.
 *
 * Simulates the DAO timelock executing the proposal (6 calls):
 *   1. CREATE2 factory → deploy TLDMinter at a deterministic address
 *   2. root.setController(address(tldMinter), true)
 *   3-6. tldMinter.batchAddToAllowlist(batch) — all 1,166 gTLDs in 4 batches
 *
 * The TLDMinter address is pre-computed from the CREATE2 formula before deployment,
 * allowing Calls 2-6 to reference it in the same proposal. Delegates can verify
 * the expected address matches the bytecode hash before voting.
 *
 * To verify locally:
 *   Clone: git clone https://github.com/estmcmxci/dao-proposals.git
 *   Checkout: git checkout <commit>
 *   cp .env.example .env && echo "MAINNET_RPC_URL=<your-rpc>" >> .env
 *   Run: forge test --match-path "src/ens/proposals/tld-oracle-v2/*" -vv
 */
contract TLDOracleV2CalldataCheck is Test {
    using stdJson for string;

    // ─────────────────────────────────────────────────────────────────
    // Mainnet Addresses
    // ─────────────────────────────────────────────────────────────────

    address constant ROOT          = 0xaB528d626EC275E3faD363fF1393A41F581c5897;
    address constant DNSSEC_IMPL   = 0x0fc3152971714E5ed7723FAFa650F86A4BaF30C5;
    address constant ENS_REGISTRY  = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant DAO_TIMELOCK  = 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7;
    address constant SC_MULTISIG   = 0xaA5cD05f6B62C3af58AE9c4F3F7A2aCC2Cdc2Cc7;
    address constant SC_CONTRACT   = 0xB8fA0cE3f91F41C5292D07475b445c35ddF63eE0;

    // Deterministic deployment proxy (EIP-2470 / standard CREATE2 factory)
    // Note: uses CREATE2_FACTORY inherited from forge-std Base.sol

    // Salt — chosen for this proposal; produces a deterministic TLDMinter address
    bytes32 constant SALT = bytes32(0);

    // ─────────────────────────────────────────────────────────────────
    // Constructor Args (Mainnet)
    // ─────────────────────────────────────────────────────────────────

    uint256 constant TIMELOCK_DURATION = 7 days;
    uint256 constant RATE_LIMIT_MAX    = 10;
    uint256 constant RATE_LIMIT_PERIOD = 7 days;
    uint256 constant PROOF_MAX_AGE     = 14 days;

    // ─────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    // ─────────────────────────────────────────────────────────────────
    // Test
    // ─────────────────────────────────────────────────────────────────

    function test_proposalExecutesExpectedOutcome() public {
        // ── Pre-compute TLDMinter address ────────────────────────────
        bytes memory initCode = _buildInitCode();
        address expectedAddress = vm.computeCreate2Address(
            SALT,
            keccak256(initCode),
            CREATE2_FACTORY
        );

        // ── Simulate DAO timelock executing proposal (6 calls) ──────
        vm.startPrank(DAO_TIMELOCK);

        // Call 1: Deploy TLDMinter via CREATE2 factory
        (bool deploySuccess,) = CREATE2_FACTORY.call(
            abi.encodePacked(SALT, initCode)
        );
        assertTrue(deploySuccess, "CREATE2 deploy failed");
        assertEq(
            expectedAddress.code.length > 0,
            true,
            "TLDMinter not deployed at expected address"
        );

        // Call 2: Authorize TLDMinter as Root controller
        IRoot(ROOT).setController(expectedAddress, true);

        // Calls 3-6: Seed allowlist in 4 batches (all 1,166 TLDs)
        string[4] memory batchFiles = [
            "src/ens/proposals/tld-oracle-v2/allowlist-batch-1.json",
            "src/ens/proposals/tld-oracle-v2/allowlist-batch-2.json",
            "src/ens/proposals/tld-oracle-v2/allowlist-batch-3.json",
            "src/ens/proposals/tld-oracle-v2/allowlist-batch-4.json"
        ];

        for (uint256 i = 0; i < 4; i++) {
            string[] memory batch = _loadBatch(batchFiles[i]);
            ITLDMinter(expectedAddress).batchAddToAllowlist(batch);
        }

        vm.stopPrank();

        // ── Assertions ───────────────────────────────────────────────

        // Root controller registered
        assertTrue(
            IRoot(ROOT).controllers(expectedAddress),
            "TLDMinter not registered as Root controller"
        );

        // Spot-check: known valid post-2012 gTLDs are allowlisted
        string[7] memory knownValid = ["link", "click", "help", "gift", "property", "sexy", "hiphop"];
        for (uint256 i = 0; i < knownValid.length; i++) {
            assertTrue(
                ITLDMinter(expectedAddress).allowedTLDs(keccak256(abi.encodePacked(knownValid[i]))),
                string.concat(knownValid[i], " should be allowlisted")
            );
        }

        // Spot-check: pre-2012 gTLDs are NOT allowlisted
        string[5] memory excluded = ["com", "net", "org", "info", "biz"];
        for (uint256 i = 0; i < excluded.length; i++) {
            assertFalse(
                ITLDMinter(expectedAddress).allowedTLDs(keccak256(abi.encodePacked(excluded[i]))),
                string.concat(excluded[i], " should NOT be allowlisted")
            );
        }

        // Version check
        assertEq(ITLDMinter(expectedAddress).version(), "2.0.0", "Unexpected contract version");

        // Allowlist count
        string memory json = vm.readFile("src/ens/proposals/tld-oracle-v2/allowlist.json");
        bytes memory raw = json.parseRaw(".tlds");
        string[] memory tlds = abi.decode(raw, (string[]));
        assertEq(tlds.length, 1166, "Allowlist should contain exactly 1,166 TLDs");
    }

    // ─────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────

    /// @dev Builds the full initCode (bytecode + ABI-encoded constructor args).
    function _buildInitCode() internal view returns (bytes memory) {
        return abi.encodePacked(
            vm.getCode("TLDMinter.sol:TLDMinter"),
            abi.encode(
                DNSSEC_IMPL,
                ROOT,
                ENS_REGISTRY,
                DAO_TIMELOCK,
                SC_MULTISIG,
                SC_CONTRACT,
                TIMELOCK_DURATION,
                RATE_LIMIT_MAX,
                RATE_LIMIT_PERIOD,
                PROOF_MAX_AGE
            )
        );
    }

    /// @dev Loads a batch of TLDs from a JSON file.
    function _loadBatch(string memory path) internal view returns (string[] memory) {
        string memory json = vm.readFile(path);
        bytes memory raw = json.parseRaw(".tlds");
        return abi.decode(raw, (string[]));
    }
}
