// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";

contract VerifyAddress is Script {
    function run() public view {
        // Known values
        bytes32 expectedHash = 0x7ea0d8b2ec007ca5b475b5c17d7e653b1f593522347b7b354d385474b2faf904;
        address expectedAddress = 0x597cC13429C9A1a365c75C61a7e32Ee32e4E2A70;
        address factory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        bytes32 salt = bytes32(0);

        // Build initCode from compiled bytecode + constructor args
        bytes memory initCode = abi.encodePacked(
            vm.getCode("TLDMinter.sol:TLDMinter"),
            abi.encode(
                address(0x0fc3152971714E5ed7723FAFa650F86A4BaF30C5),
                address(0xaB528d626EC275E3faD363fF1393A41F581c5897),
                address(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e),
                address(0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7),
                address(0xaA5cD05f6B62C3af58AE9c4F3F7A2aCC2Cdc2Cc7),
                address(0xB8fA0cE3f91F41C5292D07475b445c35ddF63eE0),
                uint256(604800),
                uint256(10),
                uint256(604800),
                uint256(1209600)
            )
        );

        // Verify initCodeHash
        bytes32 computedHash = keccak256(initCode);
        console.log("=== VERIFY INITCODEHASH ===");
        console.log("expected:", vm.toString(expectedHash));
        console.log("computed:", vm.toString(computedHash));
        if (computedHash == expectedHash) {
            console.log("PASS: initCodeHash matches");
        } else {
            console.log("FAIL: initCodeHash mismatch");
        }
        console.log("");

        // Verify CREATE2 address via raw formula
        address computedAddress = address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), factory, salt, computedHash)
        ))));

        console.log("=== VERIFY CREATE2 ADDRESS ===");
        console.log("expected:", expectedAddress);
        console.log("computed:", computedAddress);
        if (computedAddress == expectedAddress) {
            console.log("PASS: CREATE2 address matches");
        } else {
            console.log("FAIL: CREATE2 address mismatch");
        }
    }
}
