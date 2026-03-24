// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";

contract ComputeAddress is Script {
    address constant FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Mainnet constructor args
    address constant DNSSEC_IMPL   = 0x0fc3152971714E5ed7723FAFa650F86A4BaF30C5;
    address constant ROOT          = 0xaB528d626EC275E3faD363fF1393A41F581c5897;
    address constant ENS_REGISTRY  = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant DAO_TIMELOCK  = 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7;
    address constant SC_MULTISIG   = 0xaA5cD05f6B62C3af58AE9c4F3F7A2aCC2Cdc2Cc7;
    address constant SC_CONTRACT   = 0xB8fA0cE3f91F41C5292D07475b445c35ddF63eE0;

    uint256 constant TIMELOCK_DURATION = 7 days;
    uint256 constant RATE_LIMIT_MAX    = 10;
    uint256 constant RATE_LIMIT_PERIOD = 7 days;
    uint256 constant PROOF_MAX_AGE     = 14 days;

    function run() public view {
        bytes memory initCode = abi.encodePacked(
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

        bytes32 initCodeHash = keccak256(initCode);
        console.log("initCodeHash:");
        console.logBytes32(initCodeHash);
        console.log("");

        bool foundClean = false;

        for (uint256 i = 0; i < 100; i++) {
            bytes32 salt = bytes32(i);
            address addr = vm.computeCreate2Address(salt, initCodeHash, FACTORY);

            // Check for 4+ leading zero bytes (first 8 hex chars are 0)
            bool isClean = uint160(addr) < (1 << 128); // top 4 bytes are zero

            if (isClean) {
                console.log("*** CLEAN ***");
                foundClean = true;
            }

            console.log("salt:", i);
            console.log("  address:", addr);

            if (isClean) {
                console.log("");
            }
        }

        if (!foundClean) {
            console.log("");
            console.log("No clean addresses found. Using salt = bytes32(0).");
        }
    }
}
