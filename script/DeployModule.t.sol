// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "src/KeyperModule.sol";
import "test/mocks/MockedContract.t.sol";
import "@solenv/Solenv.sol";

contract DeployModule is Script {
    function run() public {
        Solenv.config();
        address masterCopy = vm.envAddress("MASTER_COPY_ADDRESS");
        address proxyFactory = vm.envAddress("PROXY_FACTORY_ADDRESS");
        address rolesAuthority = address(0xBEEF);
        uint256 maxTreeDepth = 50;
        // Deploy Constants Libraries
        address constantsAddr = deployCode("Constants.sol");
        console.log("Constants deployed at: ", constantsAddr);
        // Deploy DataTypes Libraries
        address dataTypesAddr = deployCode("DataTypes.sol");
        console.log("DataTypes deployed at: ", dataTypesAddr);
        // Deploy Errors Libraries
        address errorsAddr = deployCode("Errors.sol");
        console.log("Errors deployed at: ", errorsAddr);
        // Deploy Events Libraries
        address eventsAddr = deployCode("Events.sol");
        console.log("Events deployed at: ", eventsAddr);
        vm.startBroadcast();
        MockedContract masterCopyMocked = new MockedContract();
        MockedContract proxyFactoryMocked = new MockedContract();
        KeyperModule keyperModule = new KeyperModule(
            address(masterCopyMocked),
            address(proxyFactoryMocked),
            rolesAuthority,
            maxTreeDepth
        );
        vm.stopBroadcast();
    }
}
