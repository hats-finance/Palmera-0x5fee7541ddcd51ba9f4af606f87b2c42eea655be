# **Palmera Audit Competition on Hats.finance** 


## Introduction to Hats.finance


Hats.finance builds autonomous security infrastructure for integration with major DeFi protocols to secure users' assets. 
It aims to be the decentralized choice for Web3 security, offering proactive security mechanisms like decentralized audit competitions and bug bounties. 
The protocol facilitates audit competitions to quickly secure smart contracts by having auditors compete, thereby reducing auditing costs and accelerating submissions. 
This aligns with their mission of fostering a robust, secure, and scalable Web3 ecosystem through decentralized security solutions​.

## About Hats Audit Competition


Hats Audit Competitions offer a unique and decentralized approach to enhancing the security of web3 projects. Leveraging the large collective expertise of hundreds of skilled auditors, these competitions foster a proactive bug hunting environment to fortify projects before their launch. Unlike traditional security assessments, Hats Audit Competitions operate on a time-based and results-driven model, ensuring that only successful auditors are rewarded for their contributions. This pay-for-results ethos not only allocates budgets more efficiently by paying exclusively for identified vulnerabilities but also retains funds if no issues are discovered. With a streamlined evaluation process, Hats prioritizes quality over quantity by rewarding the first submitter of a vulnerability, thus eliminating duplicate efforts and attracting top talent in web3 auditing. The process embodies Hats Finance's commitment to reducing fees, maintaining project control, and promoting high-quality security assessments, setting a new standard for decentralized security in the web3 space​​.

## Palmera Overview

Palmera streamlines your Safes operations and treasury management across multiple chains all from a single dashboard

## Competition Details


- Type: A public audit competition hosted by Palmera
- Duration: 2 weeks
- Maximum Reward: $29,883.36
- Submissions: 101
- Total Payout: $29,883.36 distributed among 30 participants.

## Scope of Audit

```
├── src
│   ├── DenyHelper.sol
│   ├── Helpers.sol
│   ├── PalmeraGuard.sol
│   ├── PalmeraModule.sol
│   ├── PalmeraRoles.sol
│   ├── ReentrancyAttack.sol
│   ├── SafeInterfaces.sol
│   ├── SigningUtils.sol
│   ├── libraries
│   │   ├── Constants.sol
│   │   ├── DataTypes.sol
│   │   ├── Errors.sol
│   │   └── Events.sol
```

Note that contracts under the **test**, **script** and lib directories are explicitely not in scope for the audit competition.

## High severity issues


- **Insufficient Access Control in execTransactionOnBehalf Due to Broad Lead Role Check**

  In the `execTransactionOnBehalf` function, there is a mechanism that allows bypassing signature verification if the caller has a Safe Lead role. However, this mechanism fails to differentiate between the various types of Safe Lead roles (`SAFE_LEAD`, `SAFE_LEAD_EXEC_ON_BEHALF_ONLY`, and `SAFE_LEAD_MODIFY_OWNERS_ONLY`). This broad lead role check results in insufficient access control because it permits any lead role to execute transactions on behalf of the safe without needing a signature verification.

The issue arises due to the `isSafeLead` function only verifying whether the caller has a general lead role, rather than distinguishing between specific roles. This general check is implemented through a simple role-checking mechanism that does not account for the exact nature of the lead role.

The proposed mitigation is to update the `execTransactionOnBehalf` function to verify specifically for the `SAFE_LEAD_EXEC_ON_BEHALF_ONLY` role before bypassing the signature verification. This adjustment would ensure more precise access control.

Additionally, while unrelated functions like `addOwnerWithThreshold` and `removeOwner` appear to be controlled by other mechanisms such as the Palmera Roles, the core concern remains with the `execTransactionOnBehalf` function’s overly broad role-checking logic.


  **Link**: [Issue #31](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/31)


- **Revocation of Multiple Safe Lead Roles Fails in disableSafeLeadRoles Function**

  The `disableSafeLeadRoles` function is intended to revoke specific Safe Lead roles from a user. However, its current implementation only revokes the first specified role and skips the others. This can lead to a situation where if a user holds multiple Safe Lead roles, such as `SAFE_LEAD_EXEC_ON_BEHALF_ONLY` and `SAFE_LEAD_MODIFY_OWNERS_ONLY`, the function will only revoke the `SAFE_LEAD_EXEC_ON_BEHALF_ONLY` and leave the `SAFE_LEAD_MODIFY_OWNERS_ONLY` role active. This results in insufficient role revocation, compromising the system’s integrity.

For example, if a user has both `SAFE_LEAD_EXEC_ON_BEHALF_ONLY` and `SAFE_LEAD_MODIFY_OWNERS_ONLY`, calling `disableSafeLeadRoles` will only revoke the `SAFE_LEAD_EXEC_ON_BEHALF_ONLY` role. Consequently, the remaining role, `SAFE_LEAD_MODIFY_OWNERS_ONLY`, is not affected and remains active.

To mitigate this issue, the `disableSafeLeadRoles` function should be updated to independently check and revoke all Safe Lead roles, regardless of their order in the conditional checks. The revised implementation ensures all roles are revoked as intended:
```solidity
function disableSafeLeadRoles(address user) private {
    RolesAuthority _authority = RolesAuthority(rolesAuthority);
    if (_authority.doesUserHaveRole(user, uint8(DataTypes.Role.SAFE_LEAD))) {
        _authority.setUserRole(user, uint8(DataTypes.Role.SAFE_LEAD), false);
    }
    if (_authority.doesUserHaveRole(user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY))) {
        _authority.setUserRole(user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY), false);
    }
    if (_authority.doesUserHaveRole(user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY))) {
        _authority.setUserRole(user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY), false);
    }
}
```


  **Link**: [Issue #37](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/37)


- **isSafeLead Function Fails to Verify Current Roles, Allowing Unauthorized Access**

  The `isSafeLead` function is designed to verify if a user is a lead for a specific safe by examining the `_safe.lead` attribute. However, this mechanism fails to account for cases where a user's Safe Lead roles have been disabled via the `disableSafeLeadRoles` function. As a result, the function neglects to check the user's current roles within the `RolesAuthority` contract, potentially leading to unauthorized access.

This issue can have serious implications, as it allows users whose roles have been revoked to still be recognized as safe leads. This oversight compromises the access control mechanism, enabling these users to perform unauthorized actions.

A proof of concept illustrates this problem:
1. A user `X` is initially set as a lead for `safe B`.
2. The `disableSafeLeadRoles` function revokes all Safe Lead roles from user `X`.
3. Despite the revocation, the `isSafeLead` function still identifies `X` as the lead for `safe B` because it only checks the `_safe.lead` attribute, ignoring the user's current roles.

The current implementation of the `isSafeLead` function needs to be enhanced to include a check against the `RolesAuthority` to ensure that the user still has the relevant Safe Lead roles. This would prevent unauthorized access by users whose roles have been revoked.


  **Link**: [Issue #38](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/38)


- **SetRole function doesn't consider safeId properly, allowing unrestricted role assignments**

  In the `setRole` function designed to assign specific roles to users for a given safe (identified by `safeId`), the current implementation fails to correctly consider the `safeId` parameter. Consequently, roles are assigned broadly to users without associating them specifically with a `safeId`, allowing users with root access to any organization to modify roles for any user across all organizations.

Scenarios illustrating the impact:
1. An organization (`uniOrg`) assigns a role to user A. A malicious attacker can create another organization (`XOrg`) and use its `safeId` to either revoke the role from user A or grant different roles, essentially hijacking control over user privileges.
2. If a user with a role (e.g., `SAFE_LEAD_MODIFY_OWNERS_ONLY`) in one organization leads a safe, they could create a new organization and assign themselves a different role (e.g., `SAFE_LEAD_EXEC_ON_BEHALF_ONLY`) in that new context.

The main impacts include:
- Malicious users could unduly assign or revoke roles, leading to unauthorized transaction executions.
- The revocation of roles can cause service denial for other organizations.

A proof of concept (PoC) demonstrates the vulnerability through specific test scenarios, where roots of different organizations can freely change roles of users, showing the exploitability of this flaw.

To mitigate this issue, roles should be assigned to users considering both `safeId` and `user` together, ensuring roles are specific to a `safeId`.


  **Link**: [Issue #70](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/70)


- **Unauthorized Access When Root Safe Joins New Organization Retaining Root Role**

  When a root safe, designated with the highest access level, exits an organization and joins a new one, it retains its root role. This misleads the contract to incorrectly recognize the safe as the root of the new organization, posing a significant risk by granting unauthorized access. The identified code in the `_createOrgOrRoot` function attributes this role to the root safe:

```solidity
        /// Assign SUPER_SAFE Role + SAFE_ROOT Role
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            newRootSafe, uint8(DataTypes.Role.ROOT_SAFE), true
        );
```

To illustrate the scenario:
1. Safe A establishes an organization and becomes its root.
2. Safe A exits this organization.
3. Safe A joins a new organization as a member.
4. The contract erroneously considers Safe A as the root in this new organization because it retained the `ROOT_SAFE` role from the previous organization.

The solution involves modifying the `addSafe` function to revoke any existing `ROOT_SAFE` role before adding the safe to a new organization. The proposed code amendment includes:

```diff
@@ -379,6 +379,14 @@ contract PalmeraModule is Auth, Helpers {
         indexSafe[org].push(safeId);
         /// Give Role SuperSafe
         RolesAuthority _authority = RolesAuthority(rolesAuthority);
+        if (_authority.doesUserHaveRole(
+                    newSafe.safe, uint8(DataTypes.Role.ROOT_SAFE))
+            ) {
+                _authority.setUserRole(
+                    newSafe.safe, uint8(DataTypes.Role.ROOT_SAFE), false
+                );
+            }
         if (
             (
```

This change ensures that the root role is revoked when the safe is added to a new organization, preventing any unauthorized access. However, there's a contention that the root role is automatically removed upon exiting an organization, making this issue invalid. Additional verification is suggested to confirm this behavior.


  **Link**: [Issue #76](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/76)

## Medium severity issues


- **Exploit in registerOrg Function Allows Denial-of-Service and Gas Griefing Attacks**

  The `registerOrg` function in a contract is vulnerable to denial-of-service (DoS) and gas griefing attacks. This scenario occurs when a malicious user front-runs a legitimate user's transaction to register an organization name. The attacker's preemptive registration of the desired name causes the legitimate user's transaction to fail, forcing them to retry with a different name. This can be repeated, continuously hindering the user's efforts. The root cause is the function's failure to adequately check for existing names before allowing new registrations. To mitigate this, it is suggested to include the caller’s address in the hash when creating an organization, ensuring name uniqueness per user and preventing such attacks.


  **Link**: [Issue #3](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/3)


- **Hardcoded Depth Tree Limit Overrides Updates in createRootSafe Function**

  In the `PalmeraModule.sol` contract, there is a function `updateDepthTreeLimit` for updating the depth tree limit, ensuring the `depthTreeLimit[org]` is set to the `newLimit`. However, there's a hardcoded depth tree limit of 8 in multiple places within the contract, such as in the `createRootSafe` function, which sets the depth tree limit to 8 by default. This hardcoding means any changes made through `updateDepthTreeLimit` won’t be reflected in these parts of the contract. The recommendation is to remove this hardcoded default to ensure the depth tree limit can be updated dynamically across the entire contract.


  **Link**: [Issue #4](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/4)


- **Denial of Service Vulnerability in Critical Organization Functions Due to Unbonded orgHash**

  Unbonded `orgHash` can potentially cause a denial of service (DOS) in core functions of a contract, including `getOrgBySafe`, `removeOrg`, and `getOrgHashBySafe`. An attacker can exploit this by creating numerous organizations, overloading the contract with unbonded `orgHash` values, thus preventing legitimate users from interacting with the contract. This could lead to serious disruptions in core functionalities such as removing organizations or retrieving organization details, ultimately risking the contract's integrity and usability. Discussions suggest implementing a whitelisting mechanism to mitigate this risk, although the potential impact of such an attack remains significant, given that core functions' availability and interaction could be compromised.


  **Link**: [Issue #10](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/10)


- **Custom Contract Can Bypass isSafe() Checks and Access PalmeraModule Functions**

  A potential security loophole allows a user to create a custom contract that emulates a Safe Smart Account Wallet by returning `1` on `getThreshold()` calls. This enables the contract to utilize the `PalmeraModule` functionality and bypass `isSafe()` restrictions. Such non-safe contracts can register organizations, create root safes, and be added as safes in `addSafe()`. Consequently, these contracts can execute unauthorized actions like `execTransactionOnBehalf()`, manipulate ownership with `addOwnerWithThreshold()` and `removeOwner()`, or perform arbitrary executions that could disrupt secure operations. It is recommended to implement stricter checks, such as using `ERC165` `supportsInterface()`, to ensure only true safe contracts pass the `isSafe()` function.


  **Link**: [Issue #24](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/24)


- **Residual states retained after organization deletion can affect new registrations.**

  When organizations are deleted, not all related state information is properly removed. This can impact new users registering organizations with the same name, causing them to inherit residual states such as `allowFeature`, `listed[org]`, and `listCount`. For example, if User A registers an organization "xyz" and sets up certain features, then deletes it, a new User B registering a new organization with the same name "xyz" will inherit these unwanted settings. This can lead to functional and security issues, forcing the new organization to take additional steps to reset these states, thus consuming more resources and effort. Clearing all related storage variables in `removeOrg` upon deletion is suggested to mitigate this problem.


  **Link**: [Issue #27](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/27)


- **Issue with setRole Function: Failing to Check `enabled` Parameter for Safe Leads**

  The `setRole` function currently assigns the `_safe.lead` attribute to a user if their role is related to leadership (e.g., `SAFE_LEAD`, `SAFE_LEAD_EXEC_ON_BEHALF_ONLY`, `SAFE_LEAD_MODIFY_OWNERS_ONLY`). However, it neglects to check whether the `enabled` boolean parameter is true before updating `_safe.lead`. This oversight can result in unauthorized role assignments, where users might be incorrectly designated as safe leads even if their role should be disabled. To mitigate this, the function should validate the `enabled` parameter before assignment, and if `enabled` is false, ensure that `_safe.lead` is revoked by setting it to `address(0)` if the user holds no other lead roles. The proposed solution includes these safety checks to maintain proper access control.


  **Link**: [Issue #41](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/41)


- **Unauthorized `createRootSafe` Calls Allow Denial of Service on Safe Composability**

  The current implementation allows the creation of a rootSafe for an organization without verifying if the provided `newRootSafe` is related or authorized. This vulnerabilty can be exploited to disrupt the safe orchestration in the palmera module. An attacker can use this flaw to perform a Denial-of-Service (DoS) by registering safes from other organizations under their own malicious organization, preventing these safes from functioning correctly within their intended hierarchies. For example, a malicious actor could front-run an `addSafe` transaction and register the safe under their malicious organization, causing the legitimate transaction to revert. A proposed solution involves adding an extra verification step to ensure that `newRootSafe` has agreed to become the root safe for the given organization.


  **Link**: [Issue #50](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/50)


- **DoS Potential with Large Number of Safe Additions in Palmera Module**

  The Palmera module allows organizations to manage safes in a hierarchical structure, where a super safe can remove its child safes. However, any safe can arbitrarily become a child of any super safe by using the `addSafe` function, which increments the `superSafeOrgSafe.child` array. This array has no limit on the number of child safes, only on hierarchy depth. When removing a safe, the system must update storage extensively by finding and updating the `safeId` in the child array and modifying child safes of the removed safe. This extensive process could lead to a Denial of Service (DoS) due to an Out of Gas (OOG) error if an excessive number of safes is involved, compromising the organization's safety. The proposed solution includes implementing limits on the `safe.child` array to prevent such scenarios.


  **Link**: [Issue #51](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/51)


- **addSafe Function Fails to Check for Removed superSafeId Causing Potential Issues**

  The `addSafe` function lacks a crucial check to ensure the provided `superSafeId` is not in a removed state, which can lead to logical inconsistencies and potential security issues. Specifically, a removed safe ID could be incorrectly set as a `superSafeId`, compromising the integrity of the hierarchical structure of safes. Safes that have been removed should not be allowed to become `superSafe` again. To mitigate this, a validation step needs to be added to confirm that the `superSafeId` is not in a removed state before adding a new safe. Although the initial debate considered this a non-issue, it was later confirmed as valid, highlighting a gap in the `addSafe` and `updateSuper` functions regarding the verification of safe states.


  **Link**: [Issue #52](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/52)


- **Denial of Service Vulnerability in `_exitSafe` Function When User Disables Module**

  The `_exitSafe` function currently contains a check for `getPreviewModule(caller)` that reverts if it returns `address(0)`. This logic can cause a Denial of Service (DoS) condition. Specifically, if users call `disableModule` on their own, subsequent calls to `_exitSafe` will fail. This vulnerability impacts the `removeWholeTree` and `disconnectSafe` functions. If `disableModule` has been invoked by the user, `_exitSafe` will revert, preventing the proper execution of these functions and potentially leading to Protocol insolvency. A suggested mitigation is updating `_exitSafe` to proceed even if `prevModule` is `address(0)` by bypassing the reversion condition. This approach ensures the function does not unnecessarily fail and that `_exitSafe` can execute properly even if the module has been deactivated.


  **Link**: [Issue #55](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/55)


- **Missing Validation for Guard and Module in addSafe Function Leads to Vulnerabilities**

  The `addSafe` function currently lacks validation to check if the `msg.sender` has enabled the guard and the `PalmeraModule`, which can lead to security concerns. Specifically, this allows safes to be added to an organization without any guard, paving the way for possible unauthorized access and Denial of Service (DoS) vulnerabilities in `disconnectSafe` and `removeWholeTree` functions. A proof-of-concept demonstrates that a safe without an enabled guard and module was successfully added. To address this, a validation check should be added to the `addSafe` function to ensure the `msg.sender` has enabled both the guard and the module. This oversight impacts other functions as well and needs comprehensive review.


  **Link**: [Issue #57](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/57)


- **Calling `disableSafeLeadRoles` Not Required for Root Safe in `removeWholeTree` Function**

  In the `removeWholeTree` function, the `disableSafeLeadRoles` function is not called for the root safe. The relevant code shows `disableSafeLeadRoles` being implemented for safes but not for the root safe, potentially causing issues if the root safe becomes a member of another organization. This omission can lead to unexpected behavior and security risks, as the root safe retains roles that should be disabled. To mitigate this, it is recommended to ensure that `disableSafeLeadRoles` is also called for the root safe to prevent any associated issues. However, a counterpoint is presented claiming the root safe is removed correctly through the `_exitSafe(rootSafe)` function, rendering the concern invalid. Verification and further deliberation are requested.


  **Link**: [Issue #72](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/72)


- **Issue with `getPreviewModule()` Function Returning Incorrect Next Pointer in Safe Contracts Version 1.3.0**

  The `getPreviewModule()` function in `Helpers.sol` has a bug when calling `safe.getModulesPaginated`. In Safe contracts version 1.3.0, used by Palmera, the function returns an incorrect next pointer, producing erroneous data. Although this issue is fixed in newer versions, Palmera remains on version 1.3.0. A related impact is found in the `execTransactionOnBehalf` function, which calls `checkSignatures` and `checkNSignatures`. Safe version 1.3.0’s `checkNSignatures` has a bug, now fixed in the latest versions. Despite the preference to use 1.3.0 due to its widespread adoption, on-chain tests with version 1.4.1 and the ERC-4337 module have passed successfully. Upgrading to a recent version of Safe is recommended.


  **Link**: [Issue #78](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/78)

## Low severity issues


- **Incorrect Calculation of PALMERA_TX_TYPEHASH in Constants Contract**

  The constant `PALMERA_TX_TYPEHASH` in the **Constants** contract is incorrectly calculated, leading to a breach of [EIP-721](https://eips.ethereum.org/EIPS/eip-712) standards. The correct keccak256 hash should be `0x33d86b91ace2c23c833e6a968f94ce2cdabd89ed7375f3d2135aa0f5a9c131b5` instead of the current value.


  **Link**: [Issue #1](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/1)


- **Incorrect Encoding of `bytes` Data and Signature Violates EIP-712 in `createDigestExecTx`**

  The `createDigestExecTx` function is incorrectly encoding `bytes` data and signatures without using keccak256 hashing, violating EIP-712 standards. This results in incorrect encoding. The recommended fix is to keccak256 hash the `bytes` arguments before computing the digest.


  **Link**: [Issue #6](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/6)


- **Enum.Operation Type Causes EIP-712 Hash Calculation Error**

  Enum.Operation is not a common type and cannot be used in EIP-712 hash calculations. Enums are derived from uint, so uint should be used instead. Using Enum.Operation results in an incorrect hash. A provided proof of concept demonstrates this issue.


  **Link**: [Issue #11](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/11)


- **Deprecation of the `this` Keyword in Solidity 0.8.23 in `domainSeparator` Function**

  The `domainSeparator()` function in `Helpers.sol` uses the deprecated `this` keyword, which can cause unexpected behavior in Solidity version 0.8.23. It is recommended to use `address(this)` instead to adhere to best practices and avoid issues with deprecated variables and functions.


  **Link**: [Issue #28](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/28)


- **Access Control Issue with `removeSafe()` Function in Palmera Documentation and Implementation**

  The current implementation of the `removeSafe()` function allows any `SafeRegistered` user to call it, contrary to the documentation that stipulates only the root safe should. This risks unauthorized access to critical functionality. It is recommended to modify the access control to ensure only root safes can call this function, adhering strictly to the protocol’s intended design.


  **Link**: [Issue #40](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/40)


- **Vulnerability in PalmeraModule Contract Allows Malicious Delegatecall to Destroy targetSafe Contract**

  The `execTransactionOnBehalf` function in the `PalmeraModule` contract lets specific roles like Safe Lead, Super Safe, and Root Safe execute transactions. A vulnerability arises if a malicious contract is targeted using `delegatecall`, allowing it to self-destruct and destroy the targetSafe contract, disrupting the organization.


  **Link**: [Issue #61](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/61)


- **Parent Child Array Not Updated After Promoting Safe to Root**

  safeRoot's `promoteRoot()` function promotes a safe to Root but fails to update the parent safe's child array, causing data inconsistency. The parent array should be updated to remove the promoted safe, preventing potential vulnerabilities. A proposed code revision includes logic to remove the promoted child from the parent's child array efficiently.


  **Link**: [Issue #89](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/89)


- **Super Safe Role Not Revoked When Root Safe Promoted and Removed**

  When a safe is removed from an organization, its roles should be revoked. However, if a super safe is promoted to root, the super safe role isn't revoked, posing a risk. The problem can be demonstrated through scenarios where safes retain super safe roles even after org exits. To resolve this, super safe roles should be revoked before the exit.


  **Link**: [Issue #92](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/92)



## Conclusion

The audit of Palmera's competition on Hats.finance highlighted numerous security vulnerabilities within the PalmeraModule contract. Major concerns included insufficient access control in the execTransactionOnBehalf function, failures in role revocation, and improper role verification which could lead to unauthorized access and operations. Medium severity issues emphasized the need for robust organization and user state management; instances like denial-of-service attacks, mismanagement of safe hierarchies, and critical function failures were identified. Low severity issues included improper calculations and encoding that violate industry standards like EIP-712, and deprecated code usage that could lead to unexpected behavior. The audit's recommendations included comprehensive role-specific validation, ensuring proper state cleanups upon organization changes, and adhering to standard coding practices to mitigate these vulnerabilities. By addressing these findings, Hats.finance can enhance Palmera’s security posture significantly, ensuring safer and more robust operations in a decentralized ecosystem.

## Disclaimer


This report does not assert that the audited contracts are completely secure. Continuous review and comprehensive testing are advised before deploying critical smart contracts.


The Palmera audit competition illustrates the collaborative effort in identifying and rectifying potential vulnerabilities, enhancing the overall security and functionality of the platform.


Hats.finance does not provide any guarantee or warranty regarding the security of this project. Smart contract software should be used at the sole risk and responsibility of users.

