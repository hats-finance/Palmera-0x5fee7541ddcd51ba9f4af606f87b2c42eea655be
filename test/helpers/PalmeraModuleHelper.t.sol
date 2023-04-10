// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "./SignDigestHelper.t.sol";
import "./SignersHelper.t.sol";
import {PalmeraModule} from "../../src/PalmeraModule.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {GnosisSafe} from "@safe-contracts/GnosisSafe.sol";
import {DeploySafeFactory} from "../../script/DeploySafeFactory.t.sol";

contract PalmeraModuleHelper is Test, SignDigestHelper, SignersHelper {
    struct PalmeraTransaction {
        address org;
        address safe;
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
    }

    PalmeraModule public keyper;
    GnosisSafe public safeHelper;

    function initHelper(PalmeraModule _keyper, uint256 numberOwners) public {
        keyper = _keyper;
        initOnwers(numberOwners);
    }

    function setGnosisSafe(address safe) public {
        safeHelper = GnosisSafe(payable(safe));
    }

    /// @notice Encode signatures for a keypertx
    function encodeSignaturesPalmeraTx(
        address caller,
        address safe,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) public view returns (bytes memory) {
        // Create encoded tx to be signed
        uint256 nonce = keyper.nonce();
        bytes32 txHashed = keyper.getTransactionHash(
            caller, safe, to, value, data, operation, nonce
        );

        address[] memory owners = safeHelper.getOwners();
        // Order owners
        address[] memory sortedOwners = sortAddresses(owners);
        uint256 threshold = safeHelper.getThreshold();

        // Get pk for the signing threshold
        uint256[] memory privateKeySafeOwners = new uint256[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            privateKeySafeOwners[i] = ownersPK[sortedOwners[i]];
        }

        bytes memory signatures = signDigestTx(privateKeySafeOwners, txHashed);

        return signatures;
    }

    /// @notice Sign keyperTx with invalid signatures (do not belong to any safe owner)
    function encodeInvalidSignaturesPalmeraTx(
        address caller,
        address safe,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) public view returns (bytes memory) {
        // Create encoded tx to be signed
        uint256 nonce = keyper.nonce();
        bytes32 txHashed = keyper.getTransactionHash(
            caller, safe, to, value, data, operation, nonce
        );

        uint256 threshold = safeHelper.getThreshold();
        // Get invalid pk for the signing threshold
        uint256[] memory invalidSafeOwnersPK = new uint256[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            invalidSafeOwnersPK[i] = invalidPrivateKeyOwners[i];
        }

        bytes memory signatures = signDigestTx(invalidSafeOwnersPK, txHashed);

        return signatures;
    }

    function createPalmeraTxHash(
        address caller,
        address safe,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 nonce
    ) public view returns (bytes32) {
        bytes32 txHashed = keyper.getTransactionHash(
            caller, safe, to, value, data, operation, nonce
        );
        return txHashed;
    }

    function createSafeProxy(uint256 numberOwners, uint256 threshold)
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
        DeploySafeFactory deploySafeFactory = new DeploySafeFactory();
        deploySafeFactory.run();

        address masterCopy = address(deploySafeFactory.gnosisSafeContract());
        address safeFactory = address(deploySafeFactory.proxyFactory());
        address rolesAuthority = address(deploySafeFactory.proxyFactory());
        uint256 maxTreeDepth = 50;
        keyper = new PalmeraModule(
            masterCopy,
            safeFactory,
            rolesAuthority,
            maxTreeDepth
        );

        require(address(keyper) != address(0), "Palmera module not deployed");
        address[] memory owners = new address[](numberOwners);
        for (uint256 i = 0; i < numberOwners; i++) {
            owners[i] = vm.addr(privateKeyOwners[i + countUsed]);
            countUsed++;
        }
        return keyper.createSafeProxy(owners, threshold);
    }
}
