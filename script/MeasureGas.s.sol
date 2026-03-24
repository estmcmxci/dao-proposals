// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IRoot {
    function setController(address controller, bool enabled) external;
}

contract MeasureGas is Script {
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
        // Load allowlist into constructor args
        string memory json = vm.readFile("src/ens/proposals/tld-oracle-v2/allowlist.json");
        bytes memory raw = json.parseRaw(".tlds");
        string[] memory tlds = abi.decode(raw, (string[]));
        console.log("Loaded TLDs:", tlds.length);
        console.log("");

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

        address expectedAddress = vm.computeCreate2Address(
            SALT, keccak256(initCode), FACTORY
        );
        console.log("Expected TLDMinter address:", expectedAddress);
        console.log("initCodeHash:", vm.toString(keccak256(initCode)));
        console.log("");

        // Two-call proposal: deploy + setController
        bytes memory call1Data = abi.encodePacked(SALT, initCode);
        bytes memory call2Data = abi.encodeWithSelector(
            IRoot.setController.selector, expectedAddress, true
        );

        console.log("=== CALLDATA SIZES ===");
        console.log("Call 1 (CREATE2 deploy + allowlist):", call1Data.length, "bytes");
        console.log("Call 2 (setController):", call2Data.length, "bytes");
        console.log("Total calldata:", call1Data.length + call2Data.length, "bytes");
        console.log("");

        // Gas measurements
        vm.startPrank(DAO_TIMELOCK);

        uint256 g0 = gasleft();
        (bool ok1,) = FACTORY.call(call1Data);
        uint256 deployGas = g0 - gasleft();
        require(ok1, "deploy failed");

        uint256 g1 = gasleft();
        IRoot(ROOT).setController(expectedAddress, true);
        uint256 controllerGas = g1 - gasleft();

        vm.stopPrank();

        uint256 totalGas = deployGas + controllerGas;

        console.log("=== GAS BREAKDOWN ===");
        console.log("Call 1 (CREATE2 deploy + allowlist):", deployGas);
        console.log("Call 2 (setController):", controllerGas);
        console.log("Total gas:", totalGas);
        console.log("");

        // Check against 30M block gas limit (with 2M buffer)
        if (totalGas > 28_000_000) {
            console.log("WARNING: Total exceeds 28M (30M limit - 2M buffer)");
            uint256 gasPerTld = deployGas / tlds.length;
            uint256 maxTlds = (28_000_000 - controllerGas) / gasPerTld;
            console.log("  Estimated gas per TLD:", gasPerTld);
            console.log("  Max TLDs in constructor:", maxTlds);
            console.log("  Remaining for batchAddToAllowlist:", tlds.length - maxTlds);
        } else {
            console.log("OK: Single proposal fits within 30M block gas limit");
            console.log("  Headroom:", 30_000_000 - totalGas, "gas");
        }
    }
}
