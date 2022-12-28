pragma solidity ^0.8.0;

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
        uint256 maxLevel = 50;
        vm.startBroadcast();
        MockedContract masterCopyMocked = new MockedContract();
        MockedContract proxyFactoryMocked = new MockedContract();
        KeyperModule keyperModule = new KeyperModule(
            address(masterCopyMocked),
            address(proxyFactoryMocked),
            rolesAuthority,
    maxLevel
        );
        vm.stopBroadcast();
    }
}
