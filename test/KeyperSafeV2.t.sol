// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SigningUtils.sol";
import "./helpers/GnosisSafeHelperV2.t.sol";
import "./helpers/KeyperModuleHelperV2.t.sol";
// import "./helpers/ReentrancyAttackHelper.t.sol";
import "./helpers/KeyperSafeBuilderV2.t.sol";
import {Constants} from "../libraries/Constants.sol";
import {Errors} from "../libraries/Errors.sol";
import {KeyperModuleV2, IGnosisSafe} from "../src/KeyperModuleV2.sol";
import {KeyperRolesV2} from "../src/KeyperRolesV2.sol";
import {DenyHelperV2} from "../src/DenyHelperV2.sol";
import {CREATE3Factory} from "@create3/CREATE3Factory.sol";
// import {Attacker} from "../src/ReentrancyAttack.sol";
import {console} from "forge-std/console.sol";

contract TestKeyperSafeV2 is Test, SigningUtils {
    KeyperModuleV2 keyperModule;
    GnosisSafeHelperV2 gnosisHelper;
    KeyperModuleHelperV2 keyperHelper;
    KeyperRolesV2 keyperRolesContract;
    KeyperSafeBuilderV2 keyperSafeBuilder;

    address gnosisSafeAddr;
    address keyperModuleAddr;
    address keyperRolesDeployed;

    // Helper mapping to keep track safes associated with a role
    mapping(string => address) keyperSafes;
    string orgName = "Main Org";
    string org2Name = "Second Org";
    string groupA1Name = "GroupA1";
    string groupA2Name = "GroupA2";
    string groupBName = "GroupB";
    string subGroupA1Name = "subGroupA1";
    string subSubgroupA1Name = "SubSubGroupA";

    function setUp() public {
        CREATE3Factory factory = new CREATE3Factory();
        bytes32 salt = keccak256(abi.encode(0xafff));
        // Predict the future address of keyper roles
        keyperRolesDeployed = factory.getDeployed(address(this), salt);

        // Init a new safe as main organization (3 owners, 1 threshold)
        gnosisHelper = new GnosisSafeHelperV2();
        gnosisSafeAddr = gnosisHelper.setupSafeEnv();

        // setting keyperRoles Address
        gnosisHelper.setKeyperRoles(keyperRolesDeployed);

        // Init KeyperModule
        address masterCopy = gnosisHelper.gnosisMasterCopy();
        address safeFactory = address(gnosisHelper.safeFactory());

        keyperModule = new KeyperModuleV2(
            masterCopy,
            safeFactory,
            address(keyperRolesDeployed)
        );
        keyperModuleAddr = address(keyperModule);
        // Init keyperModuleHelper
        keyperHelper = new KeyperModuleHelperV2();
        keyperHelper.initHelper(keyperModule, 30);
        // Update gnosisHelper
        gnosisHelper.setKeyperModule(keyperModuleAddr);
        // Enable keyper module
        gnosisHelper.enableModuleTx(gnosisSafeAddr);

        bytes memory args = abi.encode(address(keyperModuleAddr));

        bytes memory bytecode =
            abi.encodePacked(vm.getCode("KeyperRoles.sol:KeyperRoles"), args);

        keyperRolesContract = KeyperRolesV2(factory.deploy(salt, bytecode));

        keyperSafeBuilder = new KeyperSafeBuilderV2();
        keyperSafeBuilder.setGnosisHelper(GnosisSafeHelperV2(gnosisHelper));
    }

    // ! ********************** authority Test **********************************

    // Checks if authority == keyperRoles
    function testAuthorityAddress() public {
        assertEq(
            address(keyperModule.authority()), address(keyperRolesDeployed)
        );
    }

    // ! ********************** createSafeFactory Test **************************

    // Checks if a safe is created successfully from Module
    function testCreateSafeFromModule() public {
        address newSafe = keyperHelper.createSafeProxy(4, 2);
        assertFalse(newSafe == address(0));
        // Verify newSafe has keyper modulle enabled
        GnosisSafe safe = GnosisSafe(payable(newSafe));
        bool isKeyperModuleEnabled =
            safe.isModuleEnabled(address(keyperHelper.keyper()));
        assertEq(isKeyperModuleEnabled, true);
    }

//     // ! ********************** execTransactionOnBehalf Test ********************

//     // execTransactionOnBehalf
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargetSafe Type: Child
//     function testLeadExecOnBehalf() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );
//         // Execute on behalf function
//         vm.startPrank(orgAddr);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, true);
//         assertEq(receiver.balance, 2 gwei);
//     }

//     // execTransactionOnBehalf when msg.sender is a lead (not a RootSafe)
//     // Caller: safeGroupB
//     // Caller Type: safe
//     // Caller Role: SAFE_LEAD of safeSubSubGroupA1
//     // TargerSafe: safeSubSubGroupA1
//     // TargetSafe Type: group (not a child)
//     //            rootSafe
//     //           |        |
//     //  safeGroupA1       safeGroupB
//     //      |
//     // safeSubGroupA1
//     //      |
//     // safeSubSubGroupA1
//     function testLeadExecOnBehalfFromGroup() public {
//         (address orgAddr,, address safeGroupB,, address safeSubSubGroupA1) =
//         keyperSafeBuilder.setUpBaseOrgTree(
//             orgName, groupA1Name, groupBName, subGroupA1Name, subSubgroupA1Name
//         );

//         vm.deal(safeSubSubGroupA1, 100 gwei);
//         vm.deal(safeGroupB, 100 gwei);
//         address receiver = address(0xABC);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(
//             Role.SAFE_LEAD, safeGroupB, safeSubSubGroupA1, true
//         );
//         vm.stopPrank();

//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 safeGroupB, uint8(Role.SAFE_LEAD)
//             ),
//             true
//         );
//         assertEq(
//             keyperModule.isSafeLead(orgAddr, safeSubSubGroupA1, safeGroupB),
//             true
//         );
//         assertEq(
//             keyperModule.isSuperSafe(orgAddr, safeGroupB, safeSubSubGroupA1),
//             false
//         );
//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(safeGroupB);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             safeGroupB,
//             safeSubSubGroupA1,
//             receiver,
//             12 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );

//         vm.startPrank(safeGroupB);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeSubSubGroupA1,
//             receiver,
//             12 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, true);
//         assertEq(receiver.balance, 12 gwei);
//     }

//     // execTransactionOnBehalf when Rootsafe is executing on subGroupA
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeSubGroupA1
//     // TargetSafe Type: safe as a sub child
//     //            rootSafe -----------
//     //               |                |
//     //           safeGroupA1          |
//     //              |                 |
//     //           safeSubGroupA1 <-----
//     function testRootSafeExecOnBehalf() public {
//         (address orgAddr,, address safeSubGroupA1) = keyperSafeBuilder
//             .setupOrgThreeTiersTree(orgName, groupA1Name, subGroupA1Name);

//         vm.deal(orgAddr, 100 gwei);
//         vm.deal(safeSubGroupA1, 100 gwei);
//         address receiver = address(0xABC);

//         assertEq(
//             keyperRolesContract.doesUserHaveRole(orgAddr, uint8(Role.ROOT_SAFE)),
//             true
//         );
//         assertEq(
//             keyperModule.isSafeLead(orgAddr, safeSubGroupA1, orgAddr), false
//         );
//         assertEq(
//             keyperModule.isSuperSafe(orgAddr, orgAddr, safeSubGroupA1), true
//         );

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr,
//             safeSubGroupA1,
//             receiver,
//             25 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );
//         vm.startPrank(orgAddr);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeSubGroupA1,
//             receiver,
//             25 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, true);
//         assertEq(receiver.balance, 25 gwei);
//     }

//     // Revert ZeroAddressProvided() execTransactionOnBehalf when arg "to" is address(0)
//     // Scenario 1
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe as a Child
//     //            rootSafe -----------
//     //               |                |
//     //           safeGroupA1 <--------
    // function testRevertZeroAddressProvidedExecTransactionOnBehalfScenarioOne()
    //     public
    // {
    //     (address orgAddr, address safeGroupA1) =
    //         keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

    //     address receiver = address(0xABC);
    //     address fakeReceiver = address(0);

    //     // Set keyperhelper gnosis safe to org
    //     keyperHelper.setGnosisSafe(orgAddr);
    //     bytes memory emptyData;
    //     bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
    //         orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
    //     );
    //     // Execute on behalf function from a not authorized caller
    //     vm.startPrank(orgAddr);
    //     vm.expectRevert(Errors.ZeroAddressProvided.selector);
    //     keyperModule.execTransactionOnBehalf(
    //         orgAddr,
    //         safeGroupA1,
    //         fakeReceiver,
    //         2 gwei,
    //         emptyData,
    //         Enum.Operation(0),
    //         signatures
    //     );
    // }

//     // Revert ZeroAddressProvided() execTransactionOnBehalf when param "targetSafe" is address(0)
//     // Scenario 2
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe as a Child
//     //            rootSafe -----------
//     //               |                |
//     //           safeGroupA1 <--------
//     function testRevertZeroAddressProvidedExecTransactionOnBehalfScenarioTwo()
//         public
//     {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );
//         // Execute on behalf function from a not authorized caller
//         vm.startPrank(orgAddr);
//         vm.expectRevert(DenyHelper.ZeroAddressProvided.selector);
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             address(0),
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // Revert ZeroAddressProvided() execTransactionOnBehalf when param "org" is address(0)
//     // Scenario 3
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe as a Child
//     //            rootSafe -----------
//     //               |                |
//     //           safeGroupA1 <--------
//     function testRevertZeroAddressProvidedExecTransactionOnBehalfScenarioThree()
//         public
//     {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );
//         // Execute on behalf function from a not authorized caller
//         vm.startPrank(orgAddr);
//         vm.expectRevert(DenyHelper.ZeroAddressProvided.selector);
//         keyperModule.execTransactionOnBehalf(
//             address(0),
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // Revert InvalidGnosisSafe() execTransactionOnBehalf : when param "targetSafe" is not a safe
//     // Caller: orgAddr (org)
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE, SAFE_LEAD
//     // TargerSafe: fakeTargetSafe
//     // TargetSafe Type: EOA
//     function testRevertInvalidGnosisSafeExecTransactionOnBehalf() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address receiver = address(0xABC);
//         address fakeTargetSafe = address(0xFFE);

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );
//         // Execute on behalf function from a not authorized caller
//         vm.startPrank(orgAddr);
//         vm.expectRevert(KeyperModule.InvalidGnosisSafe.selector);
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             fakeTargetSafe,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // Revert NotAuthorizedAsNotSafeLead() execTransactionOnBehalf : safe lead of another org/group
//     // Caller: fakeCaller
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of the org
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRevertNotAuthorizedExecTransactionOnBehalfScenarioTwo()
//         public
//     {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         // Random wallet instead of a safe (EOA)
//         address fakeCaller = address(0xFED);
//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to org
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures;

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, fakeCaller, orgAddr, true);
//         vm.stopPrank();

//         vm.startPrank(fakeCaller);
//         vm.expectRevert(KeyperModule.NotAuthorizedAsNotSafeLead.selector);
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // execTransactionOnBehalf when SafeLead of an Org as EOA
//     // Caller: callerEOA
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of org
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testEoaCallExecTransactionOnBehalfScenarioTwo() public {
//         (address orgAddr,) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         // Random wallet instead of a safe (EOA)
//         address callerEOA = address(0xFED);
//         address receiver = address(0xABC);

//         // Set safe_lead role to fake caller
//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, callerEOA, orgAddr, true);
//         vm.stopPrank();
//         bytes memory emptyData;
//         bytes memory signatures;
//         vm.startPrank(callerEOA);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             orgAddr,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, true);
//         assertEq(receiver.balance, 2 gwei);
//     }

//     // Revert "UNAUTHORIZED" execTransactionOnBehalf (Caller is an EOA but he's not the lead (no role provided to EOA))
//     // Caller: fakeCaller
//     // Caller Type: EOA
//     // Caller Role: N/A (NO ROLE PROVIDED)
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRevertNotAuthorizedExecTransactionOnBehalfScenarioThree()
//         public
//     {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         // Random wallet instead of a safe (EOA)
//         address fakeCaller = address(0xFED);
//         address receiver = address(0xABC);

//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );
//         vm.startPrank(fakeCaller);
//         vm.expectRevert("UNAUTHORIZED");
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // Revert "GS026" execTransactionOnBehalf (invalid signatures provided)
//     // Caller: orgAddr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRevertInvalidSignatureExecOnBehalf() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         address receiver = address(0xABC);

//         // Try onbehalf with incorrect signers
//         keyperHelper.setGnosisSafe(orgAddr);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeInvalidSignaturesKeyperTx(
//             orgAddr, safeGroupA1, receiver, 2 gwei, emptyData, Enum.Operation(0)
//         );

//         vm.expectRevert("GS026");
//         // Execute invalid OnBehalf function
//         vm.startPrank(orgAddr);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, false);
//     }

//     // execTransactionOnBehalf
//     // Caller: safeGroupA1
//     // Caller Type: safe
//     // Caller Role: SUPER_SAFE of safeSubGroupA1
//     // TargerSafe: safeSubGroupA1
//     // TargetSafe Type: safe
//     //            rootSafe
//     //               |
//     //           safeGroupA1 as superSafe ---
//     //              |                        |
//     //           safeSubGroupA1 <------------
//     function testSuperSafeExecOnBehalf() public {
//         (address orgAddr, address safeGroupA1, address safeSubGroupA1) =
//         keyperSafeBuilder.setupOrgThreeTiersTree(
//             orgName, groupA1Name, subGroupA1Name
//         );

//         // Send ETH to group&subgroup
//         vm.deal(safeGroupA1, 100 gwei);
//         vm.deal(safeSubGroupA1, 100 gwei);
//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to safeGroupA1
//         keyperHelper.setGnosisSafe(safeGroupA1);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             safeGroupA1,
//             safeSubGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );

//         // Execute on behalf function
//         vm.startPrank(safeGroupA1);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeSubGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, true);
//         assertEq(receiver.balance, 2 gwei);
//     }

//     // Revert NotAuthorizedExecOnBehalf() execTransactionOnBehalf (safeSubGroupA1 is attempting to execute on its superSafe)
//     // Caller: safeSubGroupA1
//     // Caller Type: safe
//     // Caller Role: SUPER_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe as lead
//     //            rootSafe
//     //           |
//     //  safeGroupA1 <----
//     //      |            |
//     // safeSubGroupA1 ---
//     //      |
//     // safeSubSubGroupA1
//     function testRevertSuperSafeExecOnBehalf() public {
//         (
//             address orgAddr,
//             address safeGroupA1,
//             address safeSubGroupA1,
//             address safeSubSubGroupA1
//         ) = keyperSafeBuilder.setupOrgFourTiersTree(
//             orgName, groupA1Name, subGroupA1Name, subSubgroupA1Name
//         );

//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 orgAddr, uint8(Role.SUPER_SAFE)
//             ),
//             true
//         );
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 safeGroupA1, uint8(Role.SUPER_SAFE)
//             ),
//             true
//         );
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 safeSubGroupA1, uint8(Role.SUPER_SAFE)
//             ),
//             true
//         );
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 safeSubSubGroupA1, uint8(Role.SUPER_SAFE)
//             ),
//             false
//         );

//         // Send ETH to org&subgroup
//         vm.deal(orgAddr, 100 gwei);
//         vm.deal(safeGroupA1, 100 gwei);
//         address receiver = address(0xABC);

//         // Set keyperhelper gnosis safe to safeSubGroupA1
//         keyperHelper.setGnosisSafe(safeSubGroupA1);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             safeSubGroupA1,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );

//         vm.expectRevert(KeyperModule.NotAuthorizedExecOnBehalf.selector);

//         vm.startPrank(safeSubGroupA1);
//         bool result = keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//         assertEq(result, false);
//     }

//     // Revert AddresNotAllowed() execTransactionOnBehalf (safeGroupA1 is not on AllowList)
//     // Caller: safeGroupA1
//     // Caller Type: safe
//     // Caller Role: N/A
//     // TargerSafe: safeSubGroupA1
//     // TargetSafe Type: safe
//     //            rootSafe
//     //               |
//     //           safeGroupA1 as superSafe ---
//     //              |                        |
//     //           safeSubGroupA1 <------------
//     function testRevertSuperSafeExecOnBehalfIsNotAllowList() public {
//         (address orgAddr, address safeGroupA1, address safeSubGroupA1) =
//         keyperSafeBuilder.setupOrgThreeTiersTree(
//             orgName, groupA1Name, subGroupA1Name
//         );

//         // Send ETH to group&subgroup
//         vm.deal(safeGroupA1, 100 gwei);
//         vm.deal(safeSubGroupA1, 100 gwei);
//         address receiver = address(0xABC);

//         /// Enalbe allowlist
//         vm.startPrank(orgAddr);
//         keyperModule.enableAllowlist(orgAddr);
//         vm.stopPrank();

//         // Set keyperhelper gnosis safe to safeGroupA1
//         keyperHelper.setGnosisSafe(safeGroupA1);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             safeGroupA1,
//             safeSubGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );

//         // Execute on behalf function
//         vm.startPrank(safeGroupA1);
//         vm.expectRevert(DenyHelper.AddresNotAllowed.selector);
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeSubGroupA1,
//             receiver,
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // Revert AddressDenied() execTransactionOnBehalf (safeGroupA1 is on DeniedList)
//     // Caller: safeGroupA1
//     // Caller Type: safe
//     // Caller Role: N/A
//     // TargerSafe: safeSubGroupA1
//     // TargetSafe Type: safe
//     //            rootSafe
//     //               |
//     //           safeGroupA1 as superSafe ---
//     //              |                        |
//     //           safeSubGroupA1 <------------
//     // Result: Revert
//     function testRevertSuperSafeExecOnBehalfIsDenyList() public {
//         (address orgAddr, address safeGroupA1, address safeSubGroupA1) =
//         keyperSafeBuilder.setupOrgThreeTiersTree(
//             orgName, groupA1Name, subGroupA1Name
//         );

//         // Send ETH to group&subgroup
//         vm.deal(safeGroupA1, 100 gwei);
//         vm.deal(safeSubGroupA1, 100 gwei);
//         address[] memory receiver = new address[](1);
//         receiver[0] = address(0xDDD);

//         /// Enalbe allowlist
//         vm.startPrank(orgAddr);
//         keyperModule.enableDenylist(orgAddr);
//         keyperModule.addToList(orgAddr, receiver);
//         vm.stopPrank();

//         // Set keyperhelper gnosis safe to safeGroupA1
//         keyperHelper.setGnosisSafe(safeGroupA1);
//         bytes memory emptyData;
//         bytes memory signatures = keyperHelper.encodeSignaturesKeyperTx(
//             safeGroupA1,
//             safeSubGroupA1,
//             receiver[0],
//             2 gwei,
//             emptyData,
//             Enum.Operation(0)
//         );

//         // Execute on behalf function
//         vm.startPrank(safeGroupA1);
//         vm.expectRevert(DenyHelper.AddressDenied.selector);
//         keyperModule.execTransactionOnBehalf(
//             orgAddr,
//             safeSubGroupA1,
//             receiver[0],
//             2 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );
//     }

//     // ! ********************* addOwnerWithThreshold Test ***********************

//     // addOwnerWithThreshold
//     // Caller: userLeadModifyOwnersOnly
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD_MODIFY_OWNERS_ONLY of safeGroupA1
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testAddOwnerWithThreshold() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address userLeadModifyOwnersOnly = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(
//             Role.SAFE_LEAD_MODIFY_OWNERS_ONLY,
//             userLeadModifyOwnersOnly,
//             safeGroupA1,
//             true
//         );
//         vm.stopPrank();

//         gnosisHelper.updateSafeInterface(safeGroupA1);
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         address[] memory prevOwnersList = gnosisHelper.gnosisSafe().getOwners();

//         vm.startPrank(userLeadModifyOwnersOnly);
//         address newOwner = address(0xaaaf);
//         keyperModule.addOwnerWithThreshold(
//             newOwner, threshold + 1, safeGroupA1, orgAddr
//         );

//         assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold + 1);

//         address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();
//         assertEq(ownersList.length, prevOwnersList.length + 1);

//         address ownerTest;
//         for (uint256 i = 0; i < ownersList.length; i++) {
//             if (ownersList[i] == newOwner) {
//                 ownerTest = ownersList[i];
//             }
//         }
//         assertEq(ownerTest, newOwner);
//     }

//     // Revert OwnerAlreadyExists() addOwnerWithThreshold (Attempting to add an existing owner)
//     // Caller: safeLead
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of org
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertOwnerAlreadyExists() public {
//         (address orgAddr,) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         address safeLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, safeLead, orgAddr, true);
//         vm.stopPrank();

//         assertEq(keyperModule.isSafeLead(orgAddr, orgAddr, safeLead), true);

//         gnosisHelper.updateSafeInterface(orgAddr);
//         address[] memory owners = gnosisHelper.gnosisSafe().getOwners();
//         address newOwner;

//         for (uint256 i = 0; i < owners.length; i++) {
//             newOwner = owners[i];
//         }

//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         vm.startPrank(safeLead);
//         vm.expectRevert(KeyperModule.OwnerAlreadyExists.selector);
//         keyperModule.addOwnerWithThreshold(
//             newOwner, threshold + 1, orgAddr, orgAddr
//         );
//     }

//     // Revert InvalidThreshold() addOwnerWithThreshold (When threshold < 1)
//     // Scenario 1
//     // Caller: safeLead
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of org
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertInvalidThresholdAddOwnerWithThresholdScenarioOne()
//         public
//     {
//         (address orgAddr,) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         address safeLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, safeLead, orgAddr, true);
//         vm.stopPrank();

//         address newOwner = address(0xf1f1f1);
//         uint256 wrongThreshold = 0;

//         vm.startPrank(safeLead);
//         vm.expectRevert(KeyperModule.InvalidThreshold.selector);
//         keyperModule.addOwnerWithThreshold(
//             newOwner, wrongThreshold, orgAddr, orgAddr
//         );
//     }

//     // Revert InvalidThreshold() addOwnerWithThreshold (When threshold > (IGnosisSafe(targetSafe).getOwners().length.add(1)))
//     // Scenario 2
//     // Caller: safeLead
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of org
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertInvalidThresholdAddOwnerWithThresholdScenarioTwo()
//         public
//     {
//         (address orgAddr,) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         address safeLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, safeLead, orgAddr, true);
//         vm.stopPrank();

//         gnosisHelper.updateSafeInterface(orgAddr);
//         address newOwner = address(0xf1f1f1);
//         uint256 wrongThreshold =
//             gnosisHelper.gnosisSafe().getOwners().length + 2;

//         vm.startPrank(safeLead);
//         vm.expectRevert(KeyperModule.InvalidThreshold.selector);
//         keyperModule.addOwnerWithThreshold(
//             newOwner, wrongThreshold, orgAddr, orgAddr
//         );
//     }

//     // Revert NotAuthorizedAsNotSafeLead() addOwnerWithThreshold (Attempting to add an owner from an external org)
//     // Caller: org2Addr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE for org2
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertRootSafesAttemptToAddToExternalSafeOrg() public {
//         bool result = gnosisHelper.registerOrgTx(orgName);
//         keyperSafes[orgName] = address(gnosisHelper.gnosisSafe());

//         gnosisHelper.newKeyperSafe(4, 2);
//         result = gnosisHelper.registerOrgTx(org2Name);
//         keyperSafes[org2Name] = address(gnosisHelper.gnosisSafe());

//         address orgAddr = keyperSafes[orgName];
//         address org2Addr = keyperSafes[org2Name];

//         address newOwnerOnOrgA = address(0xF1F1);
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
//         vm.expectRevert(KeyperModule.NotAuthorizedAsNotSafeLead.selector);

//         vm.startPrank(org2Addr);
//         keyperModule.addOwnerWithThreshold(
//             newOwnerOnOrgA, threshold, orgAddr, orgAddr
//         );
//     }

//     // ! ********************* removeOwner Test ***********************************

//     // removeOwner
//     // Caller: userLead
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of safeGroupA1
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRemoveOwner() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address userLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, userLead, safeGroupA1, true);
//         vm.stopPrank();

//         gnosisHelper.updateSafeInterface(safeGroupA1);
//         address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

//         address prevOwner = ownersList[0];
//         address owner = ownersList[1];
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         vm.startPrank(userLead);
//         keyperModule.removeOwner(
//             prevOwner, owner, threshold, safeGroupA1, orgAddr
//         );

//         address[] memory postRemoveOwnersList =
//             gnosisHelper.gnosisSafe().getOwners();

//         assertEq(postRemoveOwnersList.length, ownersList.length - 1);
//         assertEq(gnosisHelper.gnosisSafe().isOwner(owner), false);
//         assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
//     }

//     // Revert NotAuthorizedAsNotSafeLead() removeOwner (Attempting to remove an owner from an external org)
//     // Caller: org2Addr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE of org2
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertRootSafesToAttemptToRemoveFromExternalOrg() public {
//         bool result = gnosisHelper.registerOrgTx(orgName);
//         keyperSafes[orgName] = address(gnosisHelper.gnosisSafe());

//         gnosisHelper.newKeyperSafe(4, 2);
//         result = gnosisHelper.registerOrgTx(org2Name);
//         keyperSafes[org2Name] = address(gnosisHelper.gnosisSafe());

//         address orgAddr = keyperSafes[orgName];
//         address org2Addr = keyperSafes[org2Name];

//         address prevOwnerToRemoveOnOrgA =
//             gnosisHelper.gnosisSafe().getOwners()[0];
//         address ownerToRemove = gnosisHelper.gnosisSafe().getOwners()[1];
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         vm.expectRevert(KeyperModule.NotAuthorizedAsNotSafeLead.selector);

//         vm.startPrank(org2Addr);
//         keyperModule.removeOwner(
//             prevOwnerToRemoveOnOrgA, ownerToRemove, threshold, orgAddr, orgAddr
//         );
//     }

//     // Revert OwnerNotFound() removeOwner (attempting to remove an owner that is not exist as an owner of the safe)
//     // Caller: safeLead
//     // Caller Type: EOA
//     // Caller Role: SAFE_LEAD of org
//     // TargerSafe: orgAddr
//     // TargetSafe Type: rootSafe
//     function testRevertOwnerNotFoundRemoveOwner() public {
//         bool result = gnosisHelper.registerOrgTx(orgName);
//         keyperSafes[orgName] = address(gnosisHelper.gnosisSafe());
//         vm.label(keyperSafes[orgName], orgName);

//         assertEq(result, true);

//         address orgAddr = keyperSafes[orgName];
//         address safeLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, safeLead, orgAddr, true);
//         vm.stopPrank();

//         address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

//         address prevOwner = ownersList[0];
//         address wrongOwnerToRemove = address(0xabdcf);
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         assertEq(ownersList.length, 3);

//         vm.expectRevert(KeyperModule.OwnerNotFound.selector);

//         vm.startPrank(safeLead);

//         keyperModule.removeOwner(
//             prevOwner, wrongOwnerToRemove, threshold, orgAddr, orgAddr
//         );
//     }

//     // ! ******************** registerOrg Test *************************************

//     // registerOrg
//     function testRegisterOrgFromSafe() public {
//         bool result = gnosisHelper.registerOrgTx(orgName);
//         assertEq(result, true);
//         (
//             string memory name,
//             address lead,
//             address safe,
//             address[] memory child,
//             address superSafe
//         ) = keyperModule.getOrg(gnosisSafeAddr);
//         assertEq(name, orgName);
//         assertEq(lead, address(0));
//         assertEq(safe, gnosisSafeAddr);
//         assertEq(superSafe, address(0));
//         assertEq(child.length, 0);
//         assertEq(keyperModule.isOrgRegistered(gnosisSafeAddr), true);
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(safe, uint8(Role.ROOT_SAFE)),
//             true
//         );
//     }

//     // Revert ("UNAUTHORIZED") registerOrg (address that has no roles)
//     function testRevertAuthForRegisterOrgTx() public {
//         address caller = address(0x1);
//         vm.expectRevert(bytes("UNAUTHORIZED"));
//         keyperRolesContract.setRoleCapability(
//             uint8(Role.SAFE_LEAD), caller, ADD_OWNER, true
//         );
//     }

//     // ! ******************** addGroup Test ****************************************

//     // superSafe == org
//     function testCreateGroupFromSafe() public {
//         // Set initialsafe as org
//         bool result = gnosisHelper.registerOrgTx(orgName);
//         keyperSafes[orgName] = address(gnosisHelper.gnosisSafe());
//         vm.label(keyperSafes[orgName], orgName);

//         address safeGroupA1 = gnosisHelper.newKeyperSafe(4, 2);
//         keyperSafes[groupA1Name] = address(safeGroupA1);
//         vm.label(keyperSafes[groupA1Name], groupA1Name);

//         address orgAddr = keyperSafes[orgName];
//         result = gnosisHelper.createAddGroupTx(orgAddr, orgAddr, groupA1Name);
//         assertEq(result, true);

//         (
//             string memory name,
//             address lead,
//             address safe,
//             address[] memory child,
//             address superSafe
//         ) = keyperModule.getGroupInfo(orgAddr, safeGroupA1);

//         (, address orgLead,,,) = keyperModule.getOrg(orgAddr);

//         assertEq(name, groupA1Name);
//         assertEq(lead, orgLead);
//         assertEq(safe, safeGroupA1);
//         assertEq(child.length, 0);
//         assertEq(superSafe, orgAddr);
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 orgAddr, uint8(Role.SUPER_SAFE)
//             ),
//             true
//         );
//     }

//     // superSafe != org
//     function testCreateGroupFromSafeScenario2() public {
//         (address orgAddr, address safeGroupA1, address safeSubGroupA1) =
//         keyperSafeBuilder.setupOrgThreeTiersTree(
//             orgName, groupA1Name, subGroupA1Name
//         );

//         (
//             string memory name,
//             address lead,
//             address safe,
//             address[] memory child,
//             address superSafe
//         ) = keyperModule.getGroupInfo(orgAddr, safeGroupA1);

//         assertEq(name, groupA1Name);
//         assertEq(lead, address(0));
//         assertEq(safe, safeGroupA1);
//         assertEq(child.length, 1);
//         assertEq(child[0], safeSubGroupA1);
//         assertEq(superSafe, orgAddr);

//         (
//             string memory nameSubGroup,
//             address leadSubGroup,
//             address safeSubGroup,
//             address[] memory childSubGroup,
//             address superSubGroup
//         ) = keyperModule.getGroupInfo(orgAddr, safeSubGroupA1);

//         assertEq(nameSubGroup, subGroupA1Name);
//         assertEq(leadSubGroup, address(0));
//         assertEq(safeSubGroup, safeSubGroupA1);
//         assertEq(childSubGroup.length, 0);
//         assertEq(superSubGroup, safeGroupA1);
//     }

//     // Revert ChildAlreadyExist() addGroup (Attempting to add a group when its child already exist)
//     // Caller: safeSubGroupA1
//     // Caller Type: safe
//     // Caller Role: N/A
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRevertChildrenAlreadyExistAddGroup() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address safeSubGroupA1 = gnosisHelper.newKeyperSafe(2, 1);
//         keyperSafes[subGroupA1Name] = address(safeSubGroupA1);

//         bool result =
//             gnosisHelper.createAddGroupTx(orgAddr, safeGroupA1, subGroupA1Name);
//         assertEq(result, true);

//         vm.startPrank(safeSubGroupA1);
//         vm.expectRevert(KeyperModule.ChildAlreadyExist.selector);
//         keyperModule.addGroup(orgAddr, safeGroupA1, subGroupA1Name);

//         vm.deal(safeSubGroupA1, 1 ether);
//         gnosisHelper.updateSafeInterface(safeSubGroupA1);

//         vm.expectRevert();
//         result =
//             gnosisHelper.createAddGroupTx(orgAddr, safeGroupA1, subGroupA1Name);
//     }

//     // ! ******************** removeGroup Test *************************************

//     // removeGroup
//     // Caller: orgAddr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRemoveGroupFromOrg() public {
//         (address orgAddr, address safeGroupA1, address safeSubGroupA1) =
//         keyperSafeBuilder.setupOrgThreeTiersTree(
//             orgName, groupA1Name, subGroupA1Name
//         );

//         gnosisHelper.updateSafeInterface(orgAddr);
//         bool result = gnosisHelper.createRemoveGroupTx(orgAddr, safeGroupA1);
//         assertEq(result, true);
//         assertEq(keyperModule.isSuperSafe(orgAddr, orgAddr, safeGroupA1), false);

//         // Check safeSubGroupA1 is now a child of org
//         assertEq(keyperModule.isChild(orgAddr, orgAddr, safeSubGroupA1), true);
//         // Check org is parent of safeSubGroupA1
//         assertEq(
//             keyperModule.isSuperSafe(orgAddr, orgAddr, safeSubGroupA1), true
//         );
//     }

//     /// removeGroup when org == superSafe
//     // Caller: orgAddr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     function testRemoveGroupFromSafeOrgEqSuperSafe() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         // Create a sub safe
//         address safeSubGroupA1 = gnosisHelper.newKeyperSafe(3, 2);
//         keyperSafes[subGroupA1Name] = address(safeSubGroupA1);
//         gnosisHelper.createAddGroupTx(orgAddr, safeGroupA1, subGroupA1Name);

//         gnosisHelper.updateSafeInterface(orgAddr);
//         bool result = gnosisHelper.createRemoveGroupTx(orgAddr, safeGroupA1);

//         assertEq(result, true);

//         result = keyperModule.isSuperSafe(orgAddr, orgAddr, safeGroupA1);
//         assertEq(result, false);

//         address[] memory child;
//         (,,, child,) = keyperModule.getOrg(orgAddr);
//         // Check removed group parent has subSafeGroup A as child an not safeGroupA1
//         assertEq(child.length, 1);
//         assertEq(child[0] == safeGroupA1, false);
//         assertEq(child[0] == safeSubGroupA1, true);
//         assertEq(
//             keyperModule.isChild(orgAddr, safeGroupA1, safeSubGroupA1), false
//         );
//     }

//     // ? Org call removeGroup for a group of another org
//     // Caller: orgAddr, orgAddr2
//     // Caller Type: rootSafe
//     // Caller Role: N/A
//     // TargerSafe: safeGroupA1, safeGroupA2
//     // TargetSafe Type: safe as a child
//     // Deploy 4 keyperSafes : following structure
//     //           RootOrg1                    RootOrg2
//     //              |                            |
//     //         safeGroupA1                 safeGroupA2
//     // Must Revert if RootOrg1 attempt to remove GroupA2
//     function testRevertRemoveGroupFromAnotherOrg() public {
//         (address orgAddr1, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         (address orgAddr2, address safeGroupA2) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(org2Name, groupA2Name);

//         vm.startPrank(orgAddr1);
//         vm.expectRevert(
//             KeyperModule.NotAuthorizedRemoveNonChildrenGroup.selector
//         );
//         keyperModule.removeGroup(orgAddr2, safeGroupA2);
//         vm.stopPrank();

//         vm.startPrank(orgAddr2);
//         vm.expectRevert(
//             KeyperModule.NotAuthorizedRemoveNonChildrenGroup.selector
//         );
//         keyperModule.removeGroup(orgAddr1, safeGroupA1);
//     }

//     // ? Check disableSafeLeadRoles method success
//     // groupA1 removed and it should not have any role
//     function testRemoveGroupAndCheckDisables() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         (,,,, address superSafe) =
//             keyperModule.getGroupInfo(orgAddr, safeGroupA1);

//         gnosisHelper.updateSafeInterface(orgAddr);
//         bool result = gnosisHelper.createRemoveGroupTx(orgAddr, safeGroupA1);
//         assertEq(result, true);

//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 safeGroupA1, uint8(Role.SUPER_SAFE)
//             ),
//             false
//         );
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 superSafe, uint8(Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY)
//             ),
//             false
//         );
//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 superSafe, uint8(Role.SAFE_LEAD_MODIFY_OWNERS_ONLY)
//             ),
//             false
//         );
//     }

//     // ! ******************* setRole Test *****************************************

//     // setLead as a role at setRole Test
//     // Caller: orgAddr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE, SUPER_SAFE
//     // TargerSafe: userLead
//     // TargetSafe Type: EOA
//     function testsetSafeLead() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address userLead = address(0x123);

//         vm.startPrank(orgAddr);
//         keyperModule.setRole(Role.SAFE_LEAD, userLead, safeGroupA1, true);

//         assertEq(
//             keyperRolesContract.doesUserHaveRole(
//                 userLead, uint8(Role.SAFE_LEAD)
//             ),
//             true
//         );
//     }

//     // Empower a safe to modify another safe from another org
//     // Caller: safeGroupA2
//     // Caller Type: safe
//     // Caller Role: SAFE_LEAD
//     // TargerSafe: safeGroupA1
//     // TargetSafe Type: safe
//     // Deploy 4 keyperSafes : following structure
//     //           RootOrg1                    RootOrg2
//     //              |                            |
//     //           safeGroupA1                safeGroupA2
//     // safeGroupA2 will be a safeLead of safeGroupA1
//     function testModifyFromAnotherOrg() public {
//         (address orgAddr1, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);
//         (, address safeGroupA2) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(org2Name, groupA2Name);

//         vm.startPrank(orgAddr1);
//         keyperModule.setRole(Role.SAFE_LEAD, safeGroupA2, safeGroupA1, true);
//         vm.stopPrank();

//         assertEq(
//             keyperModule.isSafeLead(orgAddr1, safeGroupA1, safeGroupA2), true
//         );

//         address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
//         address newOwner = address(0xDEF);
//         uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

//         assertEq(
//             keyperModule.isSafeOwner(IGnosisSafe(safeGroupA1), groupA1Owners[1]),
//             true
//         );

//         vm.startPrank(safeGroupA2);

//         keyperModule.addOwnerWithThreshold(
//             newOwner, threshold, safeGroupA1, orgAddr1
//         );
//         assertEq(
//             keyperModule.isSafeOwner(IGnosisSafe(safeGroupA1), newOwner), true
//         );

//         keyperModule.removeOwner(
//             groupA1Owners[0], groupA1Owners[1], threshold, safeGroupA1, orgAddr1
//         );
//         assertEq(
//             keyperModule.isSafeOwner(IGnosisSafe(safeGroupA1), groupA1Owners[1]),
//             false
//         );
//     }

//     // Attempt to set a forbidden role to an EOA
//     // Caller: orgAddr
//     // Caller Type: rootSafe
//     // Caller Role: ROOT_SAFE, SUPER_SAFE
//     // TargerSafe: user
//     // TargetSafe Type: EOA
//     function testRevertSetRoleForbidden() public {
//         (address orgAddr, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address user = address(0xABCDE);

//         vm.startPrank(orgAddr);
//         vm.expectRevert(
//             abi.encodeWithSelector(KeyperModule.SetRoleForbidden.selector, 3)
//         );
//         keyperModule.setRole(Role.ROOT_SAFE, user, safeGroupA1, true);

//         vm.expectRevert(
//             abi.encodeWithSelector(KeyperModule.SetRoleForbidden.selector, 4)
//         );
//         keyperModule.setRole(Role.SUPER_SAFE, user, safeGroupA1, true);
//     }

//     // Attempt to set a forbidden role to an EOA
//     // Caller: safeGroupA1
//     // Caller Type: safe
//     // Caller Role: SUPER_SAFE
//     // TargerSafe: user
//     // TargetSafe Type: EOA
//     function testRevertSetRolesToOrgNotRegistered() public {
//         (, address safeGroupA1) =
//             keyperSafeBuilder.setUpRootOrgAndOneGroup(orgName, groupA1Name);

//         address user = address(0xABCDE);

//         vm.startPrank(safeGroupA1);
//         vm.expectRevert("UNAUTHORIZED");
//         keyperModule.setRole(Role.SAFE_LEAD, user, safeGroupA1, true);
//     }

//     // ! ****************** Reentrancy Attack Test to execOnBehalf ***************

//     function testReentrancyAttack() public {
//         Attacker attackerContract = new Attacker(address(keyperModule));
//         AttackerHelper attackerHelper = new AttackerHelper();
//         attackerHelper.initHelper(
//             keyperModule, attackerContract, gnosisHelper, 30
//         );

//         (address orgAddr, address attacker, address victim) =
//             attackerHelper.setAttackerTree(orgName);

//         gnosisHelper.updateSafeInterface(victim);
//         attackerContract.setOwners(gnosisHelper.gnosisSafe().getOwners());

//         gnosisHelper.updateSafeInterface(attacker);
//         vm.startPrank(attacker);

//         bytes memory emptyData;
//         bytes memory signatures = attackerHelper
//             .encodeSignaturesForAttackKeyperTx(
//             attacker, victim, attacker, 5 gwei, emptyData, Enum.Operation(0)
//         );

//         bool result = attackerContract.performAttack(
//             orgAddr,
//             victim,
//             attacker,
//             5 gwei,
//             emptyData,
//             Enum.Operation(0),
//             signatures
//         );

//         assertEq(result, true);

//         // This is the expected behavior since the nonReentrant modifier is blocking the attacker from draining the victim's funds nor transfer any amount
//         assertEq(attackerContract.getBalanceFromSafe(victim), 100 gwei);
//         assertEq(attackerContract.getBalanceFromAttacker(), 0);
//     }
}
