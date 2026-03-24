// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IRoot {
    function setController(address controller, bool enabled) external;
}

contract EncodeCalldata is Script {
    using stdJson for string;

    address constant ROOT          = 0xaB528d626EC275E3faD363fF1393A41F581c5897;
    address constant DNSSEC_IMPL   = 0x0fc3152971714E5ed7723FAFa650F86A4BaF30C5;
    address constant ENS_REGISTRY  = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant DAO_TIMELOCK  = 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7;
    address constant SC_MULTISIG   = 0xaA5cD05f6B62C3af58AE9c4F3F7A2aCC2Cdc2Cc7;
    address constant SC_CONTRACT   = 0xB8fA0cE3f91F41C5292D07475b445c35ddF63eE0;
    address constant FACTORY       = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    bytes32 constant SALT = bytes32(0);

    function run() public view {
        // Load allowlist into constructor args
        string memory json = vm.readFile("src/ens/proposals/tld-oracle-v2/allowlist.json");
        bytes memory raw = json.parseRaw(".tlds");
        string[] memory tlds = abi.decode(raw, (string[]));

        // Build initCode with allowlist baked into constructor
        bytes memory initCode = abi.encodePacked(
            vm.getCode("TLDMinter.sol:TLDMinter"),
            abi.encode(
                DNSSEC_IMPL, ROOT, ENS_REGISTRY, DAO_TIMELOCK,
                SC_MULTISIG, SC_CONTRACT,
                uint256(7 days), uint256(10), uint256(7 days), uint256(14 days),
                tlds
            )
        );

        address minter = vm.computeCreate2Address(SALT, keccak256(initCode), FACTORY);

        // Call 1: CREATE2 deploy (includes allowlist in constructor)
        bytes memory call1 = abi.encodePacked(SALT, initCode);

        // Call 2: setController
        bytes memory call2 = abi.encodeWithSelector(
            IRoot.setController.selector, minter, true
        );

        console.log("=== ENCODED CALLDATA (2-call proposal) ===");
        console.log("");
        console.log("TLDMinter address:", minter);
        console.log("initCodeHash:", vm.toString(keccak256(initCode)));
        console.log("TLDs in constructor:", tlds.length);
        console.log("");

        console.log("--- Call 1: CREATE2 deploy + allowlist ---");
        console.log("target:", FACTORY);
        console.log("calldata length:", call1.length);
        console.log("calldata:");
        console.logBytes(call1);
        console.log("");

        console.log("--- Call 2: setController ---");
        console.log("target:", ROOT);
        console.log("calldata length:", call2.length);
        console.log("calldata:");
        console.logBytes(call2);
    }
}
