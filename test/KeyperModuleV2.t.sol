// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {KeyperModuleV2} from "../src/KeyperModuleV2.sol";
import {Constants} from "../libraries/Constants.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {CREATE3Factory} from "@create3/CREATE3Factory.sol";
import {KeyperRolesV2} from "../src/KeyperRolesV2.sol";
import "./helpers/GnosisSafeHelperV2.t.sol";
import {MockedContract} from "./mocks/MockedContract.t.sol";

contract KeyperModuleTestV2 is Test {
    GnosisSafeHelperV2 gnosisHelper;
    KeyperModuleV2 keyperModule;

    MockedContract public masterCopyMocked;
    MockedContract public proxyFactoryMocked;

    address org1;
    address org2;
    address groupA;
    address groupB;
    address groupC;
    address groupD;
    address keyperModuleAddr;
    address keyperRolesDeployed;
    string rootOrgName;

    // Function called before each test is run
    function setUp() public {
        // Setup Gnosis Helper
        gnosisHelper = new GnosisSafeHelperV2();
        // Setup of all Safe for Testing
        org1 = gnosisHelper.setupSafeEnv();
        org2 = gnosisHelper.setupSafeEnv();
        groupA = gnosisHelper.setupSafeEnv();
        groupB = gnosisHelper.setupSafeEnv();
        groupC = gnosisHelper.setupSafeEnv();
        groupD = gnosisHelper.setupSafeEnv();
        vm.label(org1, "Org 1");
        vm.label(org2, "Org 2");
        vm.label(groupA, "GroupA");
        vm.label(groupB, "GroupB");

        masterCopyMocked = new MockedContract();
        proxyFactoryMocked = new MockedContract();

        CREATE3Factory factory = new CREATE3Factory();
        bytes32 salt = keccak256(abi.encode(0xafff));
        // Predict the future address of keyper roles
        keyperRolesDeployed = factory.getDeployed(address(this), salt);

        // Gnosis safe call are not used during the tests, no need deployed factory/mastercopy
        keyperModule = new KeyperModuleV2(
            address(masterCopyMocked),
            address(proxyFactoryMocked),
            address(keyperRolesDeployed)
        );

        rootOrgName = "Root Org";

        keyperModuleAddr = address(keyperModule);

        bytes memory args = abi.encode(address(keyperModuleAddr));

        bytes memory bytecode =
            abi.encodePacked(vm.getCode("KeyperRoles.sol:KeyperRoles"), args);

        factory.deploy(salt, bytecode);
    }

    function testCreateRootOrg() public {
        uint256 orgId = registerOrgWithRoles(org1, rootOrgName);
        DataTypes.Tier tier;
        string memory orgname;
        address lead;
        address safe;
        uint256[] memory child;
        uint256 superSafe;
        (tier, orgname, lead, safe, child, superSafe) =
            keyperModule.getGroupInfo(orgId);
        assertEq(uint256(tier), uint256(DataTypes.Tier.ROOT));
        assertEq(orgname, rootOrgName);
        assertEq(lead, address(0));
        assertEq(safe, org1);
        assertEq(superSafe, 0);
    }

    function testAddGroupV2() public {
        uint256 orgId = registerOrgWithRoles(org1, rootOrgName);
        vm.startPrank(groupA);
        uint256 groupIdA = keyperModule.addGroup(orgId, "GroupA");
        DataTypes.Tier tier;
        string memory groupName;
        address lead;
        address safe;
        uint256[] memory child;
        uint256 superSafe;
        (tier, groupName, lead, safe, child, superSafe) =
            keyperModule.getGroupInfo(groupIdA);
        assertEq(uint256(tier), uint256(DataTypes.Tier.GROUP));
        assertEq(groupName, "GroupA");
        assertEq(safe, groupA);
        assertEq(lead, address(0));
        assertEq(superSafe, orgId);
        // TODO update with isSuperSafe function
        assertEq(keyperModule.isRootSafeOf(org1, groupIdA), true);
        vm.stopPrank();
    }

    function testExpectInvalidGroupId() public {
        uint256 orgIdNotRegistered = 2;
        vm.startPrank(groupA);
        vm.expectRevert(Errors.InvalidGroupId.selector);
        keyperModule.addGroup(orgIdNotRegistered, "GroupA");
    }

    function testExpectGroupNotRegistered() public {
        uint256 orgIdNotRegistered = 1;
        vm.startPrank(groupA);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupNotRegistered.selector, orgIdNotRegistered
            )
        );
        keyperModule.addGroup(orgIdNotRegistered, "GroupA");
    }

    function testAddSubGroup() public {
        uint256 orgId = registerOrgWithRoles(org1, rootOrgName);
        vm.startPrank(groupA);
        uint256 groupIdA = keyperModule.addGroup(orgId, "GroupA");
        vm.stopPrank();
        vm.startPrank(groupB);
        uint256 groupIdB = keyperModule.addGroup(groupIdA, "Group B");
        // TODO update with isSuperSafe function
        assertEq(keyperModule.isTreeMember(orgId, groupIdA), true);
        assertEq(keyperModule.isTreeMember(groupIdA, groupIdB), true);
    }

    // Test tree structure for groups
    //                  org1        org2
    //                  |            |
    //              groupA          groupB
    //                |
    //              groupC
    function testTreeOrgs() public {
        uint256 orgId = registerOrgWithRoles(org1, rootOrgName);
        vm.startPrank(groupA);
        uint256 groupIdA = keyperModule.addGroup(orgId, "GroupA");
        vm.stopPrank();
        vm.startPrank(groupC);
        uint256 groupIdC = keyperModule.addGroup(groupIdA, "GroupC");
        // TODO update with isSuperSafe function
        assertEq(keyperModule.isTreeMember(orgId, groupIdA), true);
        assertEq(keyperModule.isTreeMember(groupIdA, groupIdC), true);
        vm.stopPrank();
        uint256 orgId2 = registerOrgWithRoles(org2, "RootOrg2");
        vm.startPrank(groupB);
        uint256 groupIdB = keyperModule.addGroup(orgId2, "GroupB");
        assertEq(keyperModule.isTreeMember(orgId2, groupIdB), true);
    }

    // // Test transaction execution
    // function testExecKeeperTransaction() public {
    //     registerOrgWithRoles(org1, rootOrgName);
    //     vm.startPrank(org1);
    //     keyperModule.addGroup(org1, org1, "GroupA");
    // }

    // // Test is SuperSafe function
    // function testIsSuperSafe() public {
    //     registerOrgWithRoles(org1, rootOrgName);
    //     vm.startPrank(groupA);
    //     keyperModule.addGroup(org1, org1, "GroupA");
    //     vm.stopPrank();
    //     vm.startPrank(groupB);
    //     keyperModule.addGroup(org1, groupA, "groupB");
    //     vm.stopPrank();
    //     vm.startPrank(groupC);
    //     keyperModule.addGroup(org1, groupB, "GroupC");
    //     vm.stopPrank();
    //     vm.startPrank(groupD);
    //     keyperModule.addGroup(org1, groupC, "groupD");
    //     assertEq(keyperModule.isSuperSafe(org1, org1, groupA), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupA, groupB), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupB, groupC), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupC, groupD), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupB, groupD), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupA, groupD), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupD, groupA), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupB, groupA), false);
    // }

    // function testUpdateSuper() public {
    //     setUpBaseOrgTree();
    //     vm.stopPrank();
    //     (,,,, address superSafeA) = keyperModule.getGroupInfo(org1, groupC);
    //     assertEq(superSafeA, groupA);
    //     assertEq(keyperModule.isChild(org1, groupB, groupC), false);
    //     assertEq(keyperModule.isChild(org1, groupA, groupC), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupB, groupC), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupA, groupC), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupC, groupB), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupC, groupA), false);
    //     KeyperRoles authority = KeyperRoles(keyperRolesDeployed);
    //     assertEq(
    //         authority.doesUserHaveRole(groupA, uint8(Role.SUPER_SAFE)), true
    //     );
    //     assertEq(
    //         authority.doesUserHaveRole(groupB, uint8(Role.SUPER_SAFE)), false
    //     );
    //     assertEq(
    //         authority.doesUserHaveRole(groupC, uint8(Role.SUPER_SAFE)), false
    //     );
    //     vm.startPrank(org1);
    //     keyperModule.updateSuper(groupC, groupB);
    //     vm.stopPrank();
    //     (,,,, address superSafeB) = keyperModule.getGroupInfo(org1, groupC);
    //     assertEq(superSafeB, groupB);
    //     assertEq(keyperModule.isChild(org1, groupB, groupC), true);
    //     assertEq(keyperModule.isChild(org1, groupA, groupC), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupB, groupC), true);
    //     assertEq(keyperModule.isSuperSafe(org1, groupA, groupC), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupC, groupB), false);
    //     assertEq(keyperModule.isSuperSafe(org1, groupC, groupA), false);
    //     assertEq(
    //         authority.doesUserHaveRole(groupA, uint8(Role.SUPER_SAFE)), false
    //     );
    //     assertEq(
    //         authority.doesUserHaveRole(groupB, uint8(Role.SUPER_SAFE)), true
    //     );
    //     assertEq(
    //         authority.doesUserHaveRole(groupC, uint8(Role.SUPER_SAFE)), false
    //     );
    // }

    // function testRevertUpdateSuperIfActualGroupNotRegistered() public {
    //     setUpBaseOrgTree();
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             KeyperModule.GroupNotRegistered.selector, groupD
    //         )
    //     );
    //     keyperModule.updateSuper(groupD, groupB);
    // }

    // function testRevertUpdateSuperIfNewGroupNotRegistered() public {
    //     setUpBaseOrgTree();
    //     vm.startPrank(org1);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             KeyperModule.GroupNotRegistered.selector, groupD
    //         )
    //     );
    //     keyperModule.updateSuper(groupB, groupD);
    // }

    // // TODO: Should we add a custom error for a nonsafe caller?
    // function testRevertUpdateSuperIfCallerIsNotSafe() public {
    //     setUpBaseOrgTree();
    //     vm.startPrank(address(0xDDD));
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             KeyperModule.GroupNotRegistered.selector, groupA
    //         )
    //     );
    //     keyperModule.updateSuper(groupA, groupB);
    //     vm.stopPrank();
    // }

    // function testRevertUpdateSuperIfCallerNotPartofTheOrg() public {
    //     setUpBaseOrgTree();
    //     registerOrgWithRoles(org2, rootOrgName);
    //     vm.startPrank(org2);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             KeyperModule.GroupNotRegistered.selector, groupC
    //         )
    //     );
    //     keyperModule.updateSuper(groupC, groupB);
    //     vm.stopPrank();
    // }

    // Register org call with mocked call to KeyperRoles
    function registerOrgWithRoles(address org, string memory name)
        public
        returns (uint256 orgId)
    {
        vm.startPrank(org);
        orgId = keyperModule.registerOrg(name);
        vm.stopPrank();
        return orgId;
    }

    // // Register org call and tree group with several levels with mocked call to KeyperRoles
    // function setUpBaseOrgTree() public {
    //     registerOrgWithRoles(org1, rootOrgName);
    //     vm.startPrank(groupA);
    //     keyperModule.addGroup(org1, org1, "GroupA");
    //     vm.stopPrank();
    //     vm.startPrank(groupB);
    //     keyperModule.addGroup(org1, org1, "GroupB");
    //     vm.stopPrank();
    //     vm.startPrank(groupC);
    //     keyperModule.addGroup(org1, groupA, "SubGroupA");
    //     vm.stopPrank();
    // }
}
