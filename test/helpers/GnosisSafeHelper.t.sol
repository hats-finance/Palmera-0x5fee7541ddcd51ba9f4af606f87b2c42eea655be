// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../../src/SigningUtils.sol";
import "./SignDigestHelper.t.sol";
import "./SignersHelper.t.sol";
import "../../script/DeploySafeFactory.t.sol";
import {GnosisSafe} from "@safe-contracts/GnosisSafe.sol";

// Helper contract handling deployment Safe contracts
contract GnosisSafeHelper is
    Test,
    SigningUtils,
    SignDigestHelper,
    SignersHelper
{
    GnosisSafe public safe;
    DeploySafeFactory public safeFactory;

    address public keyperRolesAddr;
    address private keyperModuleAddr;
    address public keyperGuardAddr;
    address public gnosisMasterCopy;

    uint256 public salt;

    // Create new safe test environment
    // Deploy main safe contracts (GnosisSafeProxyFactory, GnosisSafe mastercopy)
    // Init signers
    // Deploy a new safe proxy
    function setupSafeEnv() public returns (address) {
        safeFactory = new DeploySafeFactory();
        safeFactory.run();
        gnosisMasterCopy = address(safeFactory.gnosisSafeContract());
        bytes memory emptyData;
        address gnosisSafeProxy = safeFactory.newSafeProxy(emptyData);
        safe = GnosisSafe(payable(gnosisSafeProxy));
        initOnwers(30);

        // Setup safe with 3 owners, 1 threshold
        address[] memory owners = new address[](3);
        owners[0] = vm.addr(privateKeyOwners[0]);
        owners[1] = vm.addr(privateKeyOwners[1]);
        owners[2] = vm.addr(privateKeyOwners[2]);
        // Update privateKeyOwners used
        updateCount(3);

        safe.setup(
            owners,
            uint256(1),
            address(0x0),
            emptyData,
            address(0x0),
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        return address(safe);
    }

    // Create new safe test environment
    // Deploy main safe contracts (GnosisSafeProxyFactory, GnosisSafe mastercopy)
    // Init signers
    // Permit create a specific numbers of owners
    // Deploy a new safe proxy
    function setupSeveralSafeEnv(uint256 initOwners) public returns (address) {
        safeFactory = new DeploySafeFactory();
        safeFactory.run();
        gnosisMasterCopy = address(safeFactory.gnosisSafeContract());
        salt++;
        bytes memory emptyData = abi.encodePacked(salt);
        address gnosisSafeProxy = safeFactory.newSafeProxy(emptyData);
        safe = GnosisSafe(payable(gnosisSafeProxy));
        initOnwers(initOwners);

        // Setup safe with 3 owners, 1 threshold
        address[] memory owners = new address[](3);
        owners[0] = vm.addr(privateKeyOwners[0]);
        owners[1] = vm.addr(privateKeyOwners[1]);
        owners[2] = vm.addr(privateKeyOwners[2]);
        // Update privateKeyOwners used
        updateCount(3);

        safe.setup(
            owners,
            uint256(1),
            address(0x0),
            emptyData,
            address(0x0),
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        return address(safe);
    }

    function setKeyperRoles(address keyperRoles) public {
        keyperRolesAddr = keyperRoles;
    }

    function setKeyperModule(address keyperModule) public {
        keyperModuleAddr = keyperModule;
    }

    function setKeyperGuard(address keyperGuard) public {
        keyperGuardAddr = keyperGuard;
    }

    // Create GnosisSafe with Keyper and send module enabled tx
    function newKeyperSafe(uint256 numberOwners, uint256 threshold)
        public
        returns (address)
    {
        require(
            privateKeyOwners.length >= numberOwners,
            "not enough initialized owners"
        );
        require(
            countUsed + numberOwners <= privateKeyOwners.length,
            "No private keys available"
        );
        require(keyperModuleAddr != address(0), "Keyper module not set");
        address[] memory owners = new address[](numberOwners);
        for (uint256 i = 0; i < numberOwners; i++) {
            owners[i] = vm.addr(privateKeyOwners[i + countUsed]);
            countUsed++;
        }
        bytes memory emptyData;
        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            address(0x0),
            emptyData,
            address(0x0),
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        address gnosisSafeProxy = safeFactory.newSafeProxy(initializer);
        safe = GnosisSafe(payable(address(gnosisSafeProxy)));

        // Enable module
        bool result = enableModuleTx(address(safe));
        require(result == true, "failed enable module");

        // Enable Guard
        result = enableGuardTx(address(safe));
        require(result == true, "failed enable guard");
        return address(safe);
    }

    function testNewKeyperSafe() public {
        setupSafeEnv();
        setKeyperModule(address(0x678));
        newKeyperSafe(4, 2);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 4);
        assertEq(safe.getThreshold(), 2);
    }

    function updateSafeInterface(address newsafe) public {
        safe = GnosisSafe(payable(address(newsafe)));
    }

    function createSafeTxHash(Transaction memory safeTx, uint256 nonce)
        public
        view
        returns (bytes32)
    {
        bytes32 txHashed = safe.getTransactionHash(
            safeTx.to,
            safeTx.value,
            safeTx.data,
            safeTx.operation,
            safeTx.safeTxGas,
            safeTx.baseGas,
            safeTx.gasPrice,
            safeTx.gasToken,
            safeTx.refundReceiver,
            nonce
        );

        return txHashed;
    }

    function createDefaultTx(address to, bytes memory data)
        public
        pure
        returns (Transaction memory)
    {
        bytes memory emptyData;
        Transaction memory defaultTx = Transaction(
            to,
            0 gwei,
            data,
            Enum.Operation(0),
            0,
            0,
            0,
            address(0),
            address(0),
            emptyData
        );
        return defaultTx;
    }

    function enableModuleTx(address safe) public returns (bool) {
        // Create enableModule calldata
        bytes memory data =
            abi.encodeWithSignature("enableModule(address)", keyperModuleAddr);

        // Create enable module safe tx
        Transaction memory mockTx = createDefaultTx(safe, data);
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function enableGuardTx(address safe) public returns (bool) {
        // Create enableModule calldata
        bytes memory data =
            abi.encodeWithSignature("setGuard(address)", keyperGuardAddr);

        // Create enable module safe tx
        Transaction memory mockTx = createDefaultTx(safe, data);
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function disableModuleTx(address prevModule, address safe)
        public
        returns (bool)
    {
        // Create enableModule calldata
        bytes memory data = abi.encodeWithSignature(
            "disableModule(address,address)", prevModule, keyperModuleAddr
        );

        // Create enable module safe tx
        Transaction memory mockTx = createDefaultTx(safe, data);
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function disableGuardTx(address safe) public returns (bool) {
        // Create enableModule calldata
        bytes memory data =
            abi.encodeWithSignature("setGuard(address)", address(0));

        // Create enable module safe tx
        Transaction memory mockTx = createDefaultTx(safe, data);
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function executeSafeTx(Transaction memory mockTx, bytes memory signatures)
        internal
        returns (bool)
    {
        bool result = safe.execTransaction(
            mockTx.to,
            mockTx.value,
            mockTx.data,
            mockTx.operation,
            mockTx.safeTxGas,
            mockTx.baseGas,
            mockTx.gasPrice,
            mockTx.gasToken,
            payable(address(0)),
            signatures
        );

        return result;
    }

    function registerOrgTx(string memory orgName) public returns (bool) {
        // Create enableModule calldata
        bytes memory data =
            abi.encodeWithSignature("registerOrg(string)", orgName);

        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);

        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createAddSquadTx(uint256 superSafe, string memory name)
        public
        returns (bool)
    {
        bytes memory data =
            abi.encodeWithSignature("addSquad(uint256,string)", superSafe, name);
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createRootSafeTx(address newRootSafe, string memory name)
        public
        returns (bool)
    {
        bytes memory data = abi.encodeWithSignature(
            "createRootSafeSquad(address,string)", newRootSafe, name
        );
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createRemoveSquadTx(uint256 squad) public returns (bool) {
        bytes memory data =
            abi.encodeWithSignature("removeSquad(uint256)", squad);
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createRemoveWholeTreeTx() public returns (bool) {
        bytes memory data = abi.encodeWithSignature("removeWholeTree()");
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createPromoteToRootTx(uint256 squad) public returns (bool) {
        bytes memory data =
            abi.encodeWithSignature("promoteRoot(uint256)", squad);
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function createDisconnectSafeTx(uint256 squad) public returns (bool) {
        bytes memory data =
            abi.encodeWithSignature("disconnectSafe(uint256)", squad);
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function execTransactionOnBehalfTx(
        bytes32 org,
        address targetSafe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes memory signaturesExec
    ) public returns (bool) {
        bytes memory internalData = abi.encodeWithSignature(
            "execTransactionOnBehalf(bytes32,address,address,uint256,bytes,uint8,bytes)",
            org,
            targetSafe,
            to,
            value,
            data,
            operation,
            signaturesExec
        );
        // Create module safe tx
        Transaction memory mockTx =
            createDefaultTx(keyperModuleAddr, internalData);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function removeOwnerTx(
        address prevOwner,
        address ownerRemoved,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    ) public returns (bool) {
        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256,address,bytes32)",
            prevOwner,
            ownerRemoved,
            threshold,
            targetSafe,
            org
        );
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function addOwnerWithThresholdTx(
        address ownerAdded,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    ) public returns (bool) {
        bytes memory data = abi.encodeWithSignature(
            "addOwnerWithThreshold(address,uint256,address,bytes32)",
            ownerAdded,
            threshold,
            targetSafe,
            org
        );
        // Create module safe tx
        Transaction memory mockTx = createDefaultTx(keyperModuleAddr, data);
        // Sign tx
        bytes memory signatures = encodeSignaturesModuleSafeTx(mockTx);
        bool result = executeSafeTx(mockTx, signatures);
        return result;
    }

    function encodeSignaturesModuleSafeTx(Transaction memory mockTx)
        public
        returns (bytes memory)
    {
        // Create encoded tx to be signed
        uint256 nonce = safe.nonce();
        bytes32 enableModuleSafeTx = createSafeTxHash(mockTx, nonce);

        address[] memory owners = safe.getOwners();
        // Order owners
        address[] memory sortedOwners = sortAddresses(owners);
        uint256 threshold = safe.getThreshold();

        // Get pk for the signing threshold
        uint256[] memory privateKeySafeOwners = new uint256[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            privateKeySafeOwners[i] = ownersPK[sortedOwners[i]];
        }

        bytes memory signatures =
            signDigestTx(privateKeySafeOwners, enableModuleSafeTx);

        return signatures;
    }
}
