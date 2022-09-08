pragma solidity ^0.8.0;
import "forge-std/Script.sol";
import "forge-std/console.sol";

import {GnosisSafeProxyFactory} from "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "@safe-contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafe} from "../src/safeMod/GnosisSafe.sol";
import {IProxyCreationCallback} from "@safe-contracts/proxies/IProxyCreationCallback.sol";

contract DeploySafeFactory is Script {
    GnosisSafeProxyFactory public proxyFactory;
    GnosisSafe public gnosisSafeContract;
    GnosisSafeProxy safeProxy;

    // Deploys a GnosisSafeProxyFactory and a modified GnosisSafe master copy
    function run() public {
        vm.startBroadcast();
        proxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeContract = new GnosisSafe();
        vm.stopBroadcast();
    }

    function newSafeProxy(bytes memory initializer)
        public
        returns (address)
    {
        uint256 nonce = uint256(keccak256(initializer));
        safeProxy = proxyFactory.createProxyWithNonce(
            address(gnosisSafeContract),
            initializer,
            nonce
        );
        return address(safeProxy);
    }

    function newSafeProxyWithCallback(bytes memory initializer, address proxyCreation)
        public
        returns (address)
    {
        uint256 nonce = uint256(keccak256(initializer));
        safeProxy = proxyFactory.createProxyWithCallback(
            address(gnosisSafeContract),
            initializer,
            nonce,
            IProxyCreationCallback(proxyCreation)
        );
        return address(safeProxy);
    }
}
