// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {
    Helpers,
    Context,
    Errors,
    Constants,
    DataTypes,
    Events,
    Address,
    GnosisSafeMath,
    Enum,
    ISafe,
    ISafeProxy
} from "./Helpers.sol";

/// @title Palmera Module
/// @custom:security-contact general@palmeradao.xyz
contract PalmeraModule is Auth, Helpers {
    using GnosisSafeMath for uint256;
    using Address for address;

    /// @dev Definition of Safe module
    string public constant NAME = "Palmera Module";
    string public constant VERSION = "0.2.0";
    /// @dev Control Nonce of the module
    uint256 public nonce;
    /// @dev indexId of the safe
    uint256 public indexId;
    /// @dev Max Depth Tree Limit
    uint256 public maxDepthTreeLimit;
    /// @dev Safe contracts
    address public immutable masterCopy;
    address public immutable proxyFactory;
    /// @dev RoleAuthority
    address public rolesAuthority;
    /// @dev Array of Orgs (based on Hash (On-chain Organisation) of the Org)
    bytes32[] private orgHash;
    /// @dev Index of Safe
    /// bytes32: Hash (On-chain Organisation) -> uint256: ID's Safes
    mapping(bytes32 => uint256[]) public indexSafe;
    /// @dev Depth Tree Limit
    /// bytes32: Hash (On-chain Organisation) -> uint256: Depth Tree Limit
    mapping(bytes32 => uint256) public depthTreeLimit;
    /// @dev Hash (On-chain Organisation) -> Safes
    /// bytes32: Hash (On-chain Organisation).   uint256:SafeId.   Safe: Safe Info
    mapping(bytes32 => mapping(uint256 => DataTypes.Safe)) public safes;

    /// @dev Modifier for Validate if Org/Safe Exist or SuperSafeNotRegistered Not
    /// @param safe ID of the safe
    modifier SafeIdRegistered(uint256 safe) {
        if (safes[getOrgBySafe(safe)][safe].safe == address(0)) {
            revert Errors.SafeIdNotRegistered(safe);
        }
        _;
    }

    /// @dev Modifier for Validate if safe caller is Registered
    /// @param safe Safe address
    modifier SafeRegistered(address safe) {
        if (
            (safe == address(0)) || safe == Constants.SENTINEL_ADDRESS
                || !isSafe(safe)
        ) {
            revert Errors.InvalidSafe(safe);
        } else if (!isSafeRegistered(safe)) {
            revert Errors.SafeNotRegistered(safe);
        }
        _;
    }

    /// @dev Modifier for Validate if the address is a Safe Multisig Wallet and Root Safe
    /// @param safe Address of the Safe Multisig Wallet
    modifier IsRootSafe(address safe) {
        if (
            (safe == address(0)) || safe == Constants.SENTINEL_ADDRESS
                || !isSafe(safe)
        ) {
            revert Errors.InvalidSafe(safe);
        } else if (!isSafeRegistered(safe)) {
            revert Errors.SafeNotRegistered(safe);
        } else if (
            safes[getOrgHashBySafe(safe)][getSafeIdBySafe(
                getOrgHashBySafe(safe), safe
            )].tier != DataTypes.Tier.ROOT
        ) {
            revert Errors.InvalidRootSafe(safe);
        }
        _;
    }

    constructor(
        address masterCopyAddress,
        address proxyFactoryAddress,
        address authorityAddress,
        uint256 maxDepthTreeLimitInitial
    ) Auth(address(0), Authority(authorityAddress)) {
        if (
            (authorityAddress == address(0)) || !masterCopyAddress.isContract()
                || !proxyFactoryAddress.isContract()
        ) revert Errors.InvalidAddressProvided();

        masterCopy = masterCopyAddress;
        proxyFactory = proxyFactoryAddress;
        rolesAuthority = authorityAddress;
        /// Index of Safes starts in 1 Always
        indexId = 1;
        maxDepthTreeLimit = maxDepthTreeLimitInitial;
    }

    /// @notice Calls execTransaction of the safe with custom checks on owners rights
    /// @param org ID's Organisation
    /// @param superSafe Safe super address
    /// @param targetSafe Safe target address
    /// @param to Address to which the transaction is being sent
    /// @param value Value (ETH) that is being sent with the transaction
    /// @param data Data payload of the transaction
    /// @param operation kind of operation (call or delegatecall)
    /// @param signatures Packed signatures data (v, r, s)
    /// @return result true if transaction was successful.
    function execTransactionOnBehalf(
        bytes32 org,
        address superSafe, // can be root or super safe
        address targetSafe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes memory signatures
    )
        external
        payable
        nonReentrant
        SafeRegistered(superSafe)
        SafeRegistered(targetSafe)
        Denied(org, to)
        returns (bool result)
    {
        address caller = _msgSender();
        // Caller is Safe Lead: bypass check of signatures
        // Caller is another kind of wallet: check if it has the corrects signatures of the root/super safe
        if (!isSafeLead(getSafeIdBySafe(org, targetSafe), caller)) {
            // Check if caller is a superSafe of the target safe (checking with isTreeMember because is the same method!!)
            if (hasNotPermissionOverTarget(superSafe, org, targetSafe)) {
                revert Errors.NotAuthorizedExecOnBehalf();
            }
            // Caller is a safe then check caller's safe signatures.
            bytes memory palmeraTxHashData = encodeTransactionData(
                /// Palmera Info
                org,
                superSafe,
                targetSafe,
                /// Transaction info
                to,
                value,
                data,
                operation,
                /// Signature info
                nonce
            );
            /// Verify Collision of Nonce with multiple txs in the same range of time, study to use a nonce per org

            ISafe leadSafe = ISafe(superSafe);
            bytes memory sortedSignatures = processAndSortSignatures(
                signatures, keccak256(palmeraTxHashData), leadSafe.getOwners()
            );
            leadSafe.checkSignatures(
                keccak256(palmeraTxHashData),
                palmeraTxHashData,
                sortedSignatures
            );
        }
        /// Increase nonce and execute transaction.
        nonce++;
        /// Execute transaction from target safe
        ISafe safeTarget = ISafe(targetSafe);
        result =
            safeTarget.execTransactionFromModule(to, value, data, operation);

        if (!result) revert Errors.TxOnBehalfExecutedFailed();
        emit Events.TxOnBehalfExecuted(
            org, caller, superSafe, targetSafe, result
        );
    }

    /// @notice This function will allow Safe Lead & Safe Lead modify only roles
    /// @notice to to add owner and set a threshold without passing by normal multisig check
    /// @dev For instance addOwnerWithThreshold can be called by Safe Lead & Safe Lead modify only roles
    /// @param ownerAdded Address of the owner to be added
    /// @param threshold Threshold of the Safe Multisig Wallet
    /// @param targetSafe Address of the Safe Multisig Wallet
    /// @param org Hash (On-chain Organisation)
    function addOwnerWithThreshold(
        address ownerAdded,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    )
        external
        validAddress(ownerAdded)
        SafeRegistered(targetSafe)
        requiresAuth
    {
        address caller = _msgSender();
        if (hasNotPermissionOverTarget(caller, org, targetSafe)) {
            revert Errors.NotAuthorizedAddOwnerWithThreshold();
        }

        ISafe safeTarget = ISafe(targetSafe);
        /// If the owner is already an owner
        if (safeTarget.isOwner(ownerAdded)) {
            revert Errors.OwnerAlreadyExists();
        }

        bytes memory data = abi.encodeWithSelector(
            ISafe.addOwnerWithThreshold.selector, ownerAdded, threshold
        );
        /// Execute transaction from target safe
        _executeModuleTransaction(targetSafe, data);
    }

    /// @notice This function will allow User Lead/Super/Root to remove an owner
    /// @dev For instance of Remove Owner of Safe, the user lead/super/root can remove an owner without passing by normal multisig check signature
    /// @param prevOwner Address of the previous owner
    /// @param ownerRemoved Address of the owner to be removed
    /// @param threshold Threshold of the Safe Multisig Wallet
    /// @param targetSafe Address of the Safe Multisig Wallet
    /// @param org Hash (On-chain Organisation)
    function removeOwner(
        address prevOwner,
        address ownerRemoved,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    ) external SafeRegistered(targetSafe) requiresAuth {
        address caller = _msgSender();
        if (
            prevOwner == address(0) || ownerRemoved == address(0)
                || prevOwner == Constants.SENTINEL_ADDRESS
                || ownerRemoved == Constants.SENTINEL_ADDRESS
        ) {
            revert Errors.ZeroAddressProvided();
        }

        if (hasNotPermissionOverTarget(caller, org, targetSafe)) {
            revert Errors.NotAuthorizedRemoveOwner();
        }
        ISafe safeTarget = ISafe(targetSafe);
        /// if Owner Not found
        if (!safeTarget.isOwner(ownerRemoved)) {
            revert Errors.OwnerNotFound();
        }

        bytes memory data = abi.encodeWithSelector(
            ISafe.removeOwner.selector, prevOwner, ownerRemoved, threshold
        );

        /// Execute transaction from target safe
        _executeModuleTransaction(targetSafe, data);
    }

    /// @notice Give user roles
    /// @dev Call must come from the root safe
    /// @param role Role to be assigned
    /// @param user User that will have specific role (Can be EAO or safe)
    /// @param safe Safe safe which will have the user permissions on
    /// @param enabled Enable or disable the role
    function setRole(
        DataTypes.Role role,
        address user,
        uint256 safe,
        bool enabled
    ) external validAddress(user) IsRootSafe(_msgSender()) requiresAuth {
        address caller = _msgSender();
        if (
            role == DataTypes.Role.ROOT_SAFE
                || role == DataTypes.Role.SUPER_SAFE
        ) {
            revert Errors.SetRoleForbidden(role);
        }
        if (!isRootSafeOf(caller, safe)) {
            revert Errors.NotAuthorizedSetRoleAnotherTree();
        }
        DataTypes.Safe storage _safe = safes[getOrgHashBySafe(caller)][safe];
        // Check if safe is part of the caller org
        if (
            role == DataTypes.Role.SAFE_LEAD
                || role == DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY
                || role == DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY
        ) {
            // Update safe/org lead
            _safe.lead = user;
        }
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(user, uint8(role), enabled);
    }

    /// @notice Register an organisation
    /// @dev Call has to be done from a safe transaction
    /// @param orgName String with of the org (This name will be hashed into smart contract)
    function registerOrg(string calldata orgName)
        external
        IsSafe(_msgSender())
        returns (uint256 safeId)
    {
        bytes32 name = keccak256(abi.encodePacked(orgName));
        address caller = _msgSender();
        safeId = _createOrgOrRoot(orgName, caller, caller);
        orgHash.push(name);
        // Setting level by Default
        depthTreeLimit[name] = 8;

        emit Events.OrganisationCreated(caller, name, orgName);
    }

    /// @notice Call has to be done from another root safe to the organisation
    /// @dev Call has to be done from a safe transaction
    /// @param newRootSafe Address of new Root Safe
    /// @param name string name of the safe
    function createRootSafe(address newRootSafe, string calldata name)
        external
        IsSafe(newRootSafe)
        IsRootSafe(_msgSender())
        requiresAuth
        returns (uint256 safeId)
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 newIndex = indexId;
        safeId = _createOrgOrRoot(name, caller, newRootSafe);
        // Setting level by default
        depthTreeLimit[org] = 8;

        emit Events.RootSafeCreated(org, newIndex, caller, newRootSafe, name);
    }

    /// @notice Add a safe to an organisation/safe
    /// @dev Call coming from the safe
    /// @param superSafe address of the superSafe
    /// @param name string name of the safe
    function addSafe(uint256 superSafe, string memory name)
        external
        SafeIdRegistered(superSafe)
        IsSafe(_msgSender())
        returns (uint256 safeId)
    {
        // check the name of safe is not empty
        if (bytes(name).length == 0) revert Errors.EmptyName();
        bytes32 org = getOrgBySafe(superSafe);
        address caller = _msgSender();
        if (isSafeRegistered(caller)) {
            revert Errors.SafeAlreadyRegistered(caller);
        }
        // check to verify if the caller is already exist in the org
        if (isTreeMember(superSafe, getSafeIdBySafe(org, caller))) {
            revert Errors.SafeAlreadyRegistered(caller);
        }
        // check if the superSafe Reached Depth Tree Limit
        if (isLimitLevel(superSafe)) {
            revert Errors.TreeDepthLimitReached(depthTreeLimit[org]);
        }
        /// Create a new safe
        DataTypes.Safe storage newSafe = safes[org][indexId];
        /// Add to org root/safe
        DataTypes.Safe storage superSafeOrgSafe = safes[org][superSafe];
        /// Add child to superSafe
        safeId = indexId;
        superSafeOrgSafe.child.push(safeId);

        newSafe.safe = caller;
        newSafe.name = name;
        newSafe.superSafe = superSafe;
        indexSafe[org].push(safeId);
        indexId++;
        /// Give Role SuperSafe
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        if (
            (
                !_authority.doesUserHaveRole(
                    superSafeOrgSafe.safe, uint8(DataTypes.Role.SUPER_SAFE)
                )
            ) && (superSafeOrgSafe.child.length > 0)
        ) {
            _authority.setUserRole(
                superSafeOrgSafe.safe, uint8(DataTypes.Role.SUPER_SAFE), true
            );
        }

        emit Events.SafeCreated(
            org, safeId, newSafe.lead, caller, superSafe, name
        );
    }

    /// @notice Remove safe and reasign all child to the superSafe
    /// @dev All actions will be driven based on the caller of the method, and args
    /// @param safe address of the safe to be removed
    function removeSafe(uint256 safe)
        public
        SafeRegistered(_msgSender())
        requiresAuth
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 callerSafe = getSafeIdBySafe(org, caller);
        uint256 rootSafe = getRootSafe(safe);
        /// Avoid Replay attack
        if (safes[org][safe].tier == DataTypes.Tier.REMOVED) {
            revert Errors.SafeAlreadyRemoved();
        }
        // SuperSafe usecase : Check caller is superSafe of the safe
        if ((!isRootSafeOf(caller, safe)) && (!isSuperSafe(callerSafe, safe))) {
            revert Errors.NotAuthorizedAsNotRootOrSuperSafe();
        }
        DataTypes.Safe storage _safe = safes[org][safe];
        // Check if the safe is Root Safe and has child
        if (
            ((_safe.tier == DataTypes.Tier.ROOT) || (_safe.superSafe == 0))
                && (_safe.child.length > 0)
        ) {
            revert Errors.CannotRemoveSafeBeforeRemoveChild(_safe.child.length);
        }

        // superSafe is either an org or a safe
        DataTypes.Safe storage superSafe = safes[org][_safe.superSafe];

        /// Remove child from superSafe
        for (uint256 i = 0; i < superSafe.child.length; ++i) {
            if (superSafe.child[i] == safe) {
                superSafe.child[i] = superSafe.child[superSafe.child.length - 1];
                superSafe.child.pop();
                break;
            }
        }
        // Handle child from removed safe
        for (uint256 i = 0; i < _safe.child.length; ++i) {
            // Add removed safe child to superSafe
            superSafe.child.push(_safe.child[i]);
            DataTypes.Safe storage childrenSafe = safes[org][_safe.child[i]];
            // Update children safe superSafe reference
            childrenSafe.superSafe = _safe.superSafe;
        }
        /// we guarantee the child was moving to another SuperSafe in the Org
        /// and validate after in the Disconnect Safe method
        _safe.child = new uint256[](0);

        // Revoke roles to safe
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            _safe.safe, uint8(DataTypes.Role.SUPER_SAFE), false
        );
        // Disable safe lead role
        disableSafeLeadRoles(_safe.safe);

        // Store the name before to delete the Safe
        emit Events.SafeRemoved(
            org, safe, superSafe.lead, caller, _safe.superSafe, _safe.name
        );
        // Assign the with Root Safe (because is not part of the Tree)
        // If the Safe is not Root Safe, pass to depend on Root Safe directly
        _safe.superSafe = _safe.superSafe == 0 ? 0 : rootSafe;
        _safe.tier = _safe.tier == DataTypes.Tier.ROOT
            ? DataTypes.Tier.ROOT
            : DataTypes.Tier.REMOVED;
    }

    /// @notice Disconnect Safe of a Org
    /// @dev Disconnect Safe of a Org, Call must come from the root safe
    /// @param safe address of the safe to be updated
    function disconnectSafe(uint256 safe)
        external
        IsRootSafe(_msgSender())
        SafeIdRegistered(safe)
        requiresAuth
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 rootSafe = getSafeIdBySafe(org, caller);
        DataTypes.Safe memory disconnectSafe = safes[org][safe];
        /// RootSafe usecase : Check if the safe is Member of the Tree of the caller (rootSafe)
        if (
            (
                (!isRootSafeOf(caller, safe))
                    && (disconnectSafe.tier != DataTypes.Tier.REMOVED)
            )
                || (
                    (!isPendingRemove(rootSafe, safe))
                        && (disconnectSafe.tier == DataTypes.Tier.REMOVED)
                )
        ) {
            revert Errors.NotAuthorizedDisconnectChildrenSafe();
        }
        /// In case Root Safe Disconnect Safe without removeSafe Before
        if (disconnectSafe.tier != DataTypes.Tier.REMOVED) {
            removeSafe(safe);
        }
        // Disconnect Safe
        _exitSafe(safe);
        if (indexSafe[org].length == 0) removeOrg(org);
    }

    /// @notice Remove whole tree of a RootSafe
    /// @dev Remove whole tree of a RootSafe
    function removeWholeTree() external IsRootSafe(_msgSender()) requiresAuth {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 rootSafe = getSafeIdBySafe(org, caller);
        uint256[] memory _indexSafe = getTreeMember(rootSafe, indexSafe[org]);
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        for (uint256 j = 0; j < _indexSafe.length; j++) {
            uint256 safe = _indexSafe[j];
            DataTypes.Safe memory _safe = safes[org][safe];
            // Revoke roles to safe
            _authority.setUserRole(
                _safe.safe, uint8(DataTypes.Role.SUPER_SAFE), false
            );
            // Disable safe lead role
            disableSafeLeadRoles(safes[org][safe].safe);
            _exitSafe(safe);
        }
        // After Disconnect Root Safe
        emit Events.WholeTreeRemoved(
            org, rootSafe, caller, safes[org][rootSafe].name
        );
        _exitSafe(rootSafe);
        if (indexSafe[org].length == 0) removeOrg(org);
    }

    /// @notice Method to Promete a safe to Root Safe of an Org to Root Safe
    /// @dev Method to Promete a safe to Root Safe of an Org to Root Safe
    /// @param safe address of the safe to be updated
    function promoteRoot(uint256 safe)
        external
        IsRootSafe(_msgSender())
        SafeIdRegistered(safe)
        requiresAuth
    {
        bytes32 org = getOrgBySafe(safe);
        address caller = _msgSender();
        /// RootSafe usecase : Check if the safe is Member of the Tree of the caller (rootSafe)
        if (!isRootSafeOf(caller, safe)) {
            revert Errors.NotAuthorizedUpdateNonChildrenSafe();
        }
        DataTypes.Safe storage newRootSafe = safes[org][safe];
        /// Check if the safe is a Super Safe, and an Direct Children of thr Root Safe
        if (
            (newRootSafe.child.length <= 0)
                || (!isSuperSafe(getSafeIdBySafe(org, caller), safe))
        ) {
            revert Errors.NotAuthorizedUpdateNonSuperSafe();
        }
        /// Give Role RootSafe if not have it
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            newRootSafe.safe, uint8(DataTypes.Role.ROOT_SAFE), true
        );
        // Update Tier
        newRootSafe.tier = DataTypes.Tier.ROOT;
        // Update Root Safe
        newRootSafe.lead = address(0);
        newRootSafe.superSafe = 0;
        emit Events.RootSafePromoted(
            org, safe, caller, newRootSafe.safe, newRootSafe.name
        );
    }

    /// @notice update superSafe of a safe
    /// @dev Update the superSafe of a safe with a new superSafe, Call must come from the root safe
    /// @param safe address of the safe to be updated
    /// @param newSuper address of the new superSafe
    function updateSuper(uint256 safe, uint256 newSuper)
        external
        IsRootSafe(_msgSender())
        SafeIdRegistered(newSuper)
        requiresAuth
    {
        bytes32 org = getOrgBySafe(safe);
        address caller = _msgSender();
        /// RootSafe usecase : Check if the safe is Member of the Tree of the caller (rootSafe)
        if (!isRootSafeOf(caller, safe)) {
            revert Errors.NotAuthorizedUpdateNonChildrenSafe();
        }
        // Validate are the same org
        if (org != getOrgBySafe(newSuper)) {
            revert Errors.NotAuthorizedUpdateSafeToOtherOrg();
        }
        /// Check if the new Super Safe is Reached Depth Tree Limit
        if (isLimitLevel(newSuper)) {
            revert Errors.TreeDepthLimitReached(depthTreeLimit[org]);
        }
        DataTypes.Safe storage _safe = safes[org][safe];
        /// SuperSafe is either an Org or a Safe
        DataTypes.Safe storage oldSuper = safes[org][_safe.superSafe];

        /// Remove child from superSafe
        for (uint256 i = 0; i < oldSuper.child.length; ++i) {
            if (oldSuper.child[i] == safe) {
                oldSuper.child[i] = oldSuper.child[oldSuper.child.length - 1];
                oldSuper.child.pop();
                break;
            }
        }
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        /// Revoke SuperSafe and SafeLead if don't have any child, and is not organisation
        if (oldSuper.child.length == 0) {
            _authority.setUserRole(
                oldSuper.safe, uint8(DataTypes.Role.SUPER_SAFE), false
            );
            /// TODO: verify if the oldSuper need or not the Safe Lead role (after MVP)
        }

        /// Update safe superSafe
        _safe.superSafe = newSuper;
        DataTypes.Safe storage newSuperSafe = safes[org][newSuper];
        /// Add safe to new superSafe
        /// Give Role SuperSafe if not have it
        if (
            !_authority.doesUserHaveRole(
                newSuperSafe.safe, uint8(DataTypes.Role.SUPER_SAFE)
            )
        ) {
            _authority.setUserRole(
                newSuperSafe.safe, uint8(DataTypes.Role.SUPER_SAFE), true
            );
        }
        newSuperSafe.child.push(safe);
        emit Events.SafeSuperUpdated(
            org,
            safe,
            _safe.lead,
            caller,
            getSafeIdBySafe(org, oldSuper.safe),
            newSuper
        );
    }

    /// @dev Method to update Depth Tree Limit
    /// @param newLimit new Depth Tree Limit
    function updateDepthTreeLimit(uint256 newLimit)
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 rootSafe = getSafeIdBySafe(org, caller);
        if ((newLimit > maxDepthTreeLimit) || (newLimit <= depthTreeLimit[org]))
        {
            revert Errors.InvalidLimit();
        }
        emit Events.NewLimitLevel(
            org, rootSafe, caller, depthTreeLimit[org], newLimit
        );
        depthTreeLimit[org] = newLimit;
    }

    /// List of the Methods of DenyHelpers
    /// Any changes in this five methods, must be validate into the abstract contract DenyHelper

    /// @dev Funtion to Add Wallet to the List based on Approach of Safe Contract - Owner Manager
    /// @param users Array of Address of the Wallet to be added to the List
    function addToList(address[] memory users)
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        if (users.length == 0) revert Errors.ZeroAddressProvided();
        bytes32 org = getOrgHashBySafe(_msgSender());
        if (!allowFeature[org] && !denyFeature[org]) {
            revert Errors.DenyHelpersDisabled();
        }
        address currentWallet = Constants.SENTINEL_ADDRESS;
        for (uint256 i = 0; i < users.length; ++i) {
            address wallet = users[i];
            if (
                wallet == address(0) || wallet == Constants.SENTINEL_ADDRESS
                    || wallet == address(this) || currentWallet == wallet
            ) revert Errors.InvalidAddressProvided();
            // Avoid duplicate wallet
            if (listed[org][wallet] != address(0)) {
                revert Errors.UserAlreadyOnList();
            }
            // Add wallet to List
            listed[org][currentWallet] = wallet;
            currentWallet = wallet;
        }
        listed[org][currentWallet] = Constants.SENTINEL_ADDRESS;
        listCount[org] += users.length;
        emit Events.AddedToList(users);
    }

    /// @dev Function to Drop Wallet from the List  based on Approach of Safe Contract - Owner Manager
    /// @param user Array of Address of the Wallet to be dropped of the List
    function dropFromList(address user)
        external
        validAddress(user)
        IsRootSafe(_msgSender())
        requiresAuth
    {
        bytes32 org = getOrgHashBySafe(_msgSender());
        if (!allowFeature[org] && !denyFeature[org]) {
            revert Errors.DenyHelpersDisabled();
        }
        if (listCount[org] == 0) revert Errors.ListEmpty();
        if (!isListed(org, user)) revert Errors.InvalidAddressProvided();
        address prevUser = getPrevUser(org, user);
        listed[org][prevUser] = listed[org][user];
        listed[org][user] = address(0);
        listCount[org] = listCount[org] > 1 ? listCount[org].sub(1) : 0;
        emit Events.DroppedFromList(user);
    }

    /// @dev Method to Enable Allowlist
    function enableAllowlist() external IsRootSafe(_msgSender()) requiresAuth {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = true;
        denyFeature[org] = false;
    }

    /// @dev Method to Enable Allowlist
    function enableDenylist() external IsRootSafe(_msgSender()) requiresAuth {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = false;
        denyFeature[org] = true;
    }

    /// @dev Method to Disable All
    function disableDenyHelper()
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = false;
        denyFeature[org] = false;
    }

    // List of Helpers

    /// @notice Get all the information about a safe
    /// @dev Method for getting all info of a safe
    /// @param safe uint256 of the safe
    /// @return all the information about a safe
    function getSafeInfo(uint256 safe)
        public
        view
        SafeIdRegistered(safe)
        returns (
            DataTypes.Tier,
            string memory,
            address,
            address,
            uint256[] memory,
            uint256
        )
    {
        bytes32 org = getOrgBySafe(safe);
        return (
            safes[org][safe].tier,
            safes[org][safe].name,
            safes[org][safe].lead,
            safes[org][safe].safe,
            safes[org][safe].child,
            safes[org][safe].superSafe
        );
    }

    /// @notice This function checks that caller has permission (as Root/Super/Lead safe) of the target safe
    /// @param caller Caller's address
    /// @param org Hash (On-chain Organisation)
    /// @param targetSafe Address of the target Safe Multisig Wallet
    function hasNotPermissionOverTarget(
        address caller,
        bytes32 org,
        address targetSafe
    ) public view returns (bool hasPermission) {
        hasPermission = !isRootSafeOf(caller, getSafeIdBySafe(org, targetSafe))
            && !isSuperSafe(
                getSafeIdBySafe(org, caller), getSafeIdBySafe(org, targetSafe)
            ) && !isSafeLead(getSafeIdBySafe(org, targetSafe), caller);
        return hasPermission;
    }

    /// @notice check if the organisation is registered
    /// @param org address
    /// @return bool
    function isOrgRegistered(bytes32 org) public view returns (bool) {
        if (indexSafe[org].length == 0 || org == bytes32(0)) return false;
        return true;
    }

    /// @notice Check if the address, is a rootSafe of the safe within an organisation
    /// @param safe ID's of the child safe/safe
    /// @param root address of Root Safe of the safe
    /// @return bool
    function isRootSafeOf(address root, uint256 safe)
        public
        view
        SafeIdRegistered(safe)
        returns (bool)
    {
        if (root == address(0) || safe == 0) return false;
        bytes32 org = getOrgBySafe(safe);
        uint256 rootSafe = getSafeIdBySafe(org, root);
        if (rootSafe == 0) return false;
        return (
            (safes[org][rootSafe].tier == DataTypes.Tier.ROOT)
                && (isTreeMember(rootSafe, safe))
        );
    }

    /// @notice Check if the safe is a Is Tree Member of another safe
    /// @param superSafe ID's of the superSafe
    /// @param safe ID's of the safe
    /// @return isMember
    function isTreeMember(uint256 superSafe, uint256 safe)
        public
        view
        returns (bool isMember)
    {
        if (superSafe == 0 || safe == 0) return false;
        bytes32 org = getOrgBySafe(superSafe);
        DataTypes.Safe memory childSafe = safes[org][safe];
        if (childSafe.safe == address(0)) return false;
        if (superSafe == safe) return true;
        (isMember,,) = _seekMember(superSafe, safe);
    }

    /// @dev Method to validate if is Depth Tree Limit
    /// @param superSafe ID's of Safe
    /// @return bool
    function isLimitLevel(uint256 superSafe) public view returns (bool) {
        if ((superSafe == 0) || (superSafe > indexId)) return false;
        bytes32 org = getOrgBySafe(superSafe);
        (, uint256 level,) = _seekMember(indexId + 1, superSafe);
        return level >= depthTreeLimit[org];
    }

    /// @dev Method to Validate is ID Safe a SuperSafe of a Safe
    /// @param safe ID's of the safe
    /// @param superSafe ID's of the Safe
    /// @return bool
    function isSuperSafe(uint256 superSafe, uint256 safe)
        public
        view
        returns (bool)
    {
        if (superSafe == 0 || safe == 0) return false;
        bytes32 org = getOrgBySafe(superSafe);
        DataTypes.Safe memory childSafe = safes[org][safe];
        // Check if the Child Safe is was removed or not Exist and Return False
        if (
            (childSafe.safe == address(0))
                || (childSafe.tier == DataTypes.Tier.REMOVED)
                || (childSafe.tier == DataTypes.Tier.ROOT)
        ) {
            return false;
        }
        return (childSafe.superSafe == superSafe);
    }

    /// @dev Method to Validate is ID Safe is Pending to Disconnect (was Removed by SuperSafe)
    /// @param safe ID's of the safe
    /// @param rootSafe ID's of Root Safe
    /// @return bool
    function isPendingRemove(uint256 rootSafe, uint256 safe)
        public
        view
        returns (bool)
    {
        DataTypes.Safe memory childSafe = safes[getOrgBySafe(safe)][safe];
        // Check if the Child Safe is was removed or not Exist and Return False
        if (
            (childSafe.safe == address(0))
                || (childSafe.tier == DataTypes.Tier.safe)
                || (childSafe.tier == DataTypes.Tier.ROOT)
        ) {
            return false;
        }
        return (childSafe.superSafe == rootSafe);
    }

    function isSafeRegistered(address safe) public view returns (bool) {
        if ((safe == address(0)) || safe == Constants.SENTINEL_ADDRESS) {
            return false;
        }
        if (getOrgHashBySafe(safe) == bytes32(0)) return false;
        if (getSafeIdBySafe(getOrgHashBySafe(safe), safe) == 0) return false;
        return true;
    }

    /// @dev Method to get Root Safe of a Safe
    /// @param safeId ID's of the safe
    /// @return rootSafeId uint256 Root Safe Id's
    function getRootSafe(uint256 safeId)
        public
        view
        returns (uint256 rootSafeId)
    {
        bytes32 org = getOrgBySafe(safeId);
        DataTypes.Safe memory childSafe = safes[org][safeId];
        if (childSafe.superSafe == 0) return safeId;
        (,, rootSafeId) = _seekMember(indexId + 1, safeId);
    }

    /// @notice Get the safe address of a safe
    /// @dev Method for getting the safe address of a safe
    /// @param safe uint256 of the safe
    /// @return safe address
    function getSafeAddress(uint256 safe)
        public
        view
        SafeIdRegistered(safe)
        returns (address)
    {
        bytes32 org = getOrgBySafe(safe);
        return safes[org][safe].safe;
    }

    /// @dev Method to get Org by Safe
    /// @param safe address of Safe
    /// @return Org Hashed Name
    function getOrgHashBySafe(address safe) public view returns (bytes32) {
        for (uint256 i = 0; i < orgHash.length; ++i) {
            if (getSafeIdBySafe(orgHash[i], safe) != 0) {
                return orgHash[i];
            }
        }
        return bytes32(0);
    }

    /// @dev Method to get Safe ID by safe address
    /// @param org bytes32 hashed name of the Organisation
    /// @param safe Safe address
    /// @return Safe ID
    function getSafeIdBySafe(bytes32 org, address safe)
        public
        view
        returns (uint256)
    {
        if (!isOrgRegistered(org)) {
            revert Errors.OrgNotRegistered(org);
        }
        /// Check if the Safe address is into an Safe mapping
        for (uint256 i = 0; i < indexSafe[org].length; ++i) {
            if (safes[org][indexSafe[org][i]].safe == safe) {
                return indexSafe[org][i];
            }
        }
        return 0;
    }

    /// @notice call to get the orgHash based on safe id
    /// @dev Method to get the hashed orgHash based on safe id
    /// @param safe uint256 of the safe
    /// @return orgSafe Hash (On-chain Organisation)
    function getOrgBySafe(uint256 safe) public view returns (bytes32 orgSafe) {
        if ((safe == 0) || (safe > indexId)) revert Errors.InvalidSafeId();
        for (uint256 i = 0; i < orgHash.length; ++i) {
            if (safes[orgHash[i]][safe].safe != address(0)) {
                orgSafe = orgHash[i];
            }
        }
        if (orgSafe == bytes32(0)) revert Errors.SafeIdNotRegistered(safe);
    }

    /// @notice Check if a user is an safe lead of a safe/org
    /// @param safe address of the safe
    /// @param user address of the user that is a lead or not
    /// @return bool
    function isSafeLead(uint256 safe, address user)
        public
        view
        returns (bool)
    {
        bytes32 org = getOrgBySafe(safe);
        DataTypes.Safe memory _safe = safes[org][safe];
        if (_safe.safe == address(0)) return false;
        if (_safe.lead == user) {
            return true;
        }
        return false;
    }

    /// @notice Refactoring method for Create Org or RootSafe
    /// @dev Method Private for Create Org or RootSafe
    /// @param name String Name of the Organisation
    /// @param caller Safe Caller to Create Org or RootSafe
    /// @param newRootSafe Safe Address to Create Org or RootSafe
    function _createOrgOrRoot(
        string memory name,
        address caller,
        address newRootSafe
    ) private returns (uint256 safeId) {
        if (bytes(name).length == 0) {
            revert Errors.EmptyName();
        }
        bytes32 org = caller == newRootSafe
            ? bytes32(keccak256(abi.encodePacked(name)))
            : getOrgHashBySafe(caller);
        if (isOrgRegistered(org) && caller == newRootSafe) {
            revert Errors.OrgAlreadyRegistered(org);
        }
        if (isSafeRegistered(newRootSafe)) {
            revert Errors.SafeAlreadyRegistered(newRootSafe);
        }
        safeId = indexId;
        safes[org][safeId] = DataTypes.Safe({
            tier: DataTypes.Tier.ROOT,
            name: name,
            lead: address(0),
            safe: newRootSafe,
            child: new uint256[](0),
            superSafe: 0
        });
        indexSafe[org].push(safeId);
        indexId++;

        /// Assign SUPER_SAFE Role + SAFE_ROOT Role
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            newRootSafe, uint8(DataTypes.Role.ROOT_SAFE), true
        );
        _authority.setUserRole(
            newRootSafe, uint8(DataTypes.Role.SUPER_SAFE), true
        );
    }

    /// @dev Function for refactoring DisconnectSafe Method, and RemoveWholeTree in one Method
    /// @param safe ID's of the organisation
    function _exitSafe(uint256 safe) private {
        bytes32 org = getOrgBySafe(safe);
        address _safe = safes[org][safe].safe;
        address caller = _msgSender();
        ISafe safeTarget = ISafe(_safe);
        removeIndexSafe(org, safe);
        delete safes[org][safe];

        /// Disable Guard
        bytes memory data =
            abi.encodeWithSelector(ISafe.setGuard.selector, address(0));
        /// Execute transaction from target safe
        _executeModuleTransaction(_safe, data);

        /// Disable Module
        address prevModule = getPreviewModule(caller);
        if (prevModule == address(0)) {
            revert Errors.PreviewModuleNotFound(_safe);
        }
        data = abi.encodeWithSelector(
            ISafe.disableModule.selector, prevModule, address(this)
        );
        /// Execute transaction from target safe
        _executeModuleTransaction(_safe, data);

        emit Events.SafeDisconnected(org, safe, address(safeTarget), caller);
    }

    /// @notice disable safe lead roles
    /// @dev Associated roles: SAFE_LEAD || SAFE_LEAD_EXEC_ON_BEHALF_ONLY || SAFE_LEAD_MODIFY_OWNERS_ONLY
    /// @param user Address of the user to disable roles
    function disableSafeLeadRoles(address user) private {
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        if (_authority.doesUserHaveRole(user, uint8(DataTypes.Role.SAFE_LEAD)))
        {
            _authority.setUserRole(user, uint8(DataTypes.Role.SAFE_LEAD), false);
        } else if (
            _authority.doesUserHaveRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY)
            )
        ) {
            _authority.setUserRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY), false
            );
        } else if (
            _authority.doesUserHaveRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY)
            )
        ) {
            _authority.setUserRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY), false
            );
        }
    }

    /// @notice Private method to remove indexId from mapping of indexes into organisations
    /// @param org ID's of the organisation
    /// @param safe uint256 of the safe
    function removeIndexSafe(bytes32 org, uint256 safe) private {
        for (uint256 i = 0; i < indexSafe[org].length; ++i) {
            if (indexSafe[org][i] == safe) {
                indexSafe[org][i] = indexSafe[org][indexSafe[org].length - 1];
                indexSafe[org].pop();
                break;
            }
        }
    }

    /// @notice Private method to remove Org from Array of Hashes of organisations
    /// @param org ID's of the organisation
    function removeOrg(bytes32 org) private {
        for (uint256 i = 0; i < orgHash.length; ++i) {
            if (orgHash[i] == org) {
                orgHash[i] = orgHash[orgHash.length - 1];
                orgHash.pop();
                break;
            }
        }
    }

    /// @notice Method for refactoring the methods getRootSafe, isTreeMember, and isLimitTree, in one method
    /// @dev Method to Getting if is Member, the  Level and Root Safe
    /// @param superSafe ID's of the Super Safe safe
    /// @param childSafe ID's of the Child Safe
    function _seekMember(uint256 superSafe, uint256 childSafe)
        private
        view
        returns (bool isMember, uint256 level, uint256 rootSafeId)
    {
        bytes32 org = getOrgBySafe(childSafe);
        DataTypes.Safe memory _childSafe = safes[org][childSafe];
        // Check if the Child Safe is was removed or not Exist and Return False
        if (
            (_childSafe.safe == address(0))
                || (_childSafe.tier == DataTypes.Tier.REMOVED)
        ) {
            return (isMember, level, rootSafeId);
        }
        // Storage the Root Safe Address in the next superSafe is Zero
        rootSafeId = _childSafe.superSafe;
        uint256 currentSuperSafe = rootSafeId;
        level = 2; // Level start in 1
        while (currentSuperSafe != 0) {
            _childSafe = safes[org][currentSuperSafe];
            // Validate if the Current Super Safe is Equal the SuperSafe try to Found, in case is True, storage True in isMember
            isMember =
                !isMember && currentSuperSafe == superSafe ? true : isMember;
            // Validate if the Current Super Safe of the Child Safe is Equal Zero
            // Return the isMember, level and rootSafeId with actual value
            if (_childSafe.superSafe == 0) return (isMember, level, rootSafeId);
            // else update the Vaule of possible Root Safe
            else rootSafeId = _childSafe.superSafe;
            // Update the Current Super Safe with the Super Safe of the Child Safe
            currentSuperSafe = _childSafe.superSafe;
            // Update the Level for the next iteration
            level++;
        }
    }

    /// @dev Method to getting the All Gorup Member for the Tree of the Root Safe/Org indicate in the args
    /// @param rootSafe Gorup ID's of the root safe
    /// @param indexSafeByOrg Array of the Safe ID's of the Org
    /// @return indexTree Array of the Safe ID's of the Tree
    function getTreeMember(uint256 rootSafe, uint256[] memory indexSafeByOrg)
        private
        view
        returns (uint256[] memory indexTree)
    {
        uint256 index;
        for (uint256 i = 0; i < indexSafeByOrg.length; ++i) {
            if (
                (getRootSafe(indexSafeByOrg[i]) == rootSafe)
                    && (indexSafeByOrg[i] != rootSafe)
            ) {
                index++;
            }
        }
        indexTree = new uint256[](index);
        index = 0;
        for (uint256 i = 0; i < indexSafeByOrg.length; ++i) {
            if (
                (getRootSafe(indexSafeByOrg[i]) == rootSafe)
                    && (indexSafeByOrg[i] != rootSafe)
            ) {
                indexTree[index] = indexSafeByOrg[i];
                index++;
            }
        }
    }
}
