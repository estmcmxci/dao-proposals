// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface ITLDMinter {
    function batchAddToAllowlist(string[] calldata tlds) external;
}

interface IRoot {
    function setController(address controller, bool enabled) external;
}

contract MeasureBatchGas is Script {
    using stdJson for string;

    address constant ROOT          = 0xaB528d626EC275E3faD363fF1393A41F581c5897;
    address constant DNSSEC_IMPL   = 0x0fc3152971714E5ed7723FAFa650F86A4BaF30C5;
    address constant ENS_REGISTRY  = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant DAO_TIMELOCK  = 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7;
    address constant SC_MULTISIG   = 0xaA5cD05f6B62C3af58AE9c4F3F7A2aCC2Cdc2Cc7;
    address constant SC_CONTRACT   = 0xB8fA0cE3f91F41C5292D07475b445c35ddF63eE0;
    address constant FACTORY       = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    bytes32 constant SALT = bytes32(0);

    function run() public {
        // Deploy TLDMinter first so we can measure batch gas against it
        bytes memory initCode = abi.encodePacked(
            vm.getCode("TLDMinter.sol:TLDMinter"),
            abi.encode(
                DNSSEC_IMPL, ROOT, ENS_REGISTRY, DAO_TIMELOCK,
                SC_MULTISIG, SC_CONTRACT,
                uint256(7 days), uint256(10), uint256(7 days), uint256(14 days)
            )
        );

        address minter = vm.computeCreate2Address(SALT, keccak256(initCode), FACTORY);

        // Load full allowlist
        string memory json = vm.readFile("src/ens/proposals/tld-oracle-v2/allowlist.json");
        bytes memory raw = json.parseRaw(".tlds");
        string[] memory allTlds = abi.decode(raw, (string[]));

        // Deploy the contract
        vm.startPrank(DAO_TIMELOCK);
        (bool ok,) = FACTORY.call(abi.encodePacked(SALT, initCode));
        require(ok, "deploy failed");
        IRoot(ROOT).setController(minter, true);
        vm.stopPrank();

        // Test batch sizes
        uint256[7] memory sizes = [uint256(100), 150, 200, 250, 300, 350, 400];

        console.log("=== BATCH GAS MEASUREMENTS ===");
        console.log("");

        for (uint256 s = 0; s < sizes.length; s++) {
            uint256 batchSize = sizes[s];

            // Take a snapshot so each measurement starts from the same state
            uint256 snap = vm.snapshotState();

            // Build batch from the beginning of the allowlist
            string[] memory batch = new string[](batchSize);
            for (uint256 i = 0; i < batchSize; i++) {
                batch[i] = allTlds[i];
            }

            vm.prank(DAO_TIMELOCK);
            uint256 g0 = gasleft();
            ITLDMinter(minter).batchAddToAllowlist(batch);
            uint256 gasUsed = g0 - gasleft();

            uint256 perTld = gasUsed / batchSize;
            uint256 numBatches = (1166 + batchSize - 1) / batchSize;
            uint256 estimatedTotal = gasUsed * numBatches;

            console.log("--- batch size:", batchSize);
            console.log("  gas used:", gasUsed);
            console.log("  gas per TLD:", perTld);
            console.log("  batches needed:", numBatches);
            console.log("  estimated total gas:", estimatedTotal);

            // Check if fits in single proposal with Calls 1+2 (3,584,388 gas)
            uint256 totalWithDeploy = 3584388 + estimatedTotal;
            if (totalWithDeploy <= 28000000) {
                console.log("  FITS in single proposal:", totalWithDeploy);
            } else {
                console.log("  EXCEEDS single proposal:", totalWithDeploy);
            }
            console.log("");

            vm.revertToState(snap);
        }
    }
}
