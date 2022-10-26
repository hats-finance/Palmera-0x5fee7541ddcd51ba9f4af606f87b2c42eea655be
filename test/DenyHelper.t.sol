// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {KeyperModule} from "../src/KeyperModule.sol";
import {KeyperRoles} from "../src/KeyperRoles.sol";
import {DenyHelper} from "../src/DenyHelper.sol";
import {CREATE3Factory} from "@create3/CREATE3Factory.sol";

contract DenyHelperTest is Test {
    KeyperModule public keyperModule;

    address public keyperModuleAddr;
    address public keyperRolesDeployed;
    address[] public owners = new address[](5);

    function setUp() public {
        CREATE3Factory factory = new CREATE3Factory();
        bytes32 salt = keccak256(abi.encode(0xafff));
        // Predict the future address of keyper roles
        keyperRolesDeployed = factory.getDeployed(address(this), salt);

        // Gnosis safe call are not used during the tests, no need deployed factory/mastercopy
        keyperModule = new KeyperModule(
            address(0x112233),
            address(0x445566),
            address(keyperRolesDeployed)
        );

        keyperModuleAddr = address(keyperModule);

        bytes memory args = abi.encode(address(keyperModuleAddr));

        bytes memory bytecode =
            abi.encodePacked(vm.getCode("KeyperRoles.sol:KeyperRoles"), args);

        factory.deploy(salt, bytecode);
    }

    // It should add owners to
    function testAddToAllowedList() public {
        listOfOwners();
        keyperModule.addToAllowedList(owners);
        assertEq(keyperModule.allowedCount(), 5);
        assertEq(keyperModule.getPrevUser(owners[1]), owners[0]);
    }

    function testRevertAddToAllowedListZeroAddress() public {
        address[] memory voidOwnersArray = new address[](0);

        vm.expectRevert(DenyHelper.zeroAddressProvided.selector);
        keyperModule.addToAllowedList(voidOwnersArray);
    }

    function testRevertAddToAllowedListInvalidAddress() public {
        listOfInvalidOwners();

        vm.expectRevert(DenyHelper.invalidAddressProvided.selector);
        keyperModule.addToAllowedList(owners);
    }

    function testRevertAddToAllowedDuplicateAddress() public {
        listOfOwners();
        keyperModule.addToAllowedList(owners);

        address[] memory newOwner = new address[](1);
        newOwner[0] = address(0xDDD);

        vm.expectRevert(DenyHelper.userAlreadyOnAllowedList.selector);
        keyperModule.addToAllowedList(newOwner);
    }

    function testDropFromAllowedList() public {
        listOfOwners();
        keyperModule.addToAllowedList(owners);

        // Must be the address(0xCCC)
        address ownerToRemove = owners[2];

        keyperModule.dropFromAllowedList(ownerToRemove);
        assertEq(keyperModule.isAllowed(ownerToRemove), false);
        assertEq(keyperModule.getAllAllowed().length, 4);

        // Must be the address(0xEEE)
        address secOwnerToRemove = owners[4];

        keyperModule.dropFromAllowedList(secOwnerToRemove);
        assertEq(keyperModule.isAllowed(secOwnerToRemove), false);
        assertEq(keyperModule.getAllAllowed().length, 3);
    }

    function listOfOwners() internal {
        owners[0] = address(0xAAA);
        owners[1] = address(0xBBB);
        owners[2] = address(0xCCC);
        owners[3] = address(0xDDD);
        owners[4] = address(0xEEE);
    }

    ///@dev On this function we are able to set an invalid address within some array position
    ///@dev Tested with the address(0), SENTINEL_WALLETS and address(this) on different positions
    function listOfInvalidOwners() internal {
        owners[0] = address(0xAAA);
        owners[1] = address(0xBBB);
        owners[2] = address(0xCCC);
        owners[3] = address(0x1);
        owners[4] = address(0xEEE);
    }
}
