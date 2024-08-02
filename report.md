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
- Maximum Reward: $30,030
- Submissions: 101
- Total Payout: $30,030 distributed among 30 participants.

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

## Medium severity issues


- **Non-safe contracts can bypass isSafe checks to use PalmeraModule functions**

  A vulnerability allows a user to create a custom contract that returns `1` on `getThreshold()` calls, effectively bypassing `isSafe()` restrictions in the `PalmeraModule`. By doing so, these non-safe contracts can register organizations, create root safes, and be added as safes using the `addSafe()` function. The `isSafe()` function, found in `src/Helpers.sol`, checks if an address is a Safe Smart Account Wallet by verifying if the address is a contract and if the threshold is greater than zero. As a result, this vulnerability allows such contracts to execute arbitrary actions and potentially block ownership management operations. It is recommended to implement stricter checks, such as using `ERC165` `supportsInterface()` checks, to ensure contract authenticity.


  **Link**: [Issue #24](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/24)


- **Exploitable Issue with createRootSafe Allowing Denial of Service on Root Safe Addition**

  The current process for creating a rootSafe for an organization allows any address to be provided as `newRootSafe`, without verifying if the user is actually related to it. This poses a significant issue because once `newRootSafe` is registered, it can't be added again by another organization. An attacker could exploit this by registering safes from other organizations, causing a Denial of Service (DoS) that disrupts the composability of the palmera module. The malicious organization can front-run the legitimate `addSafe` calls, effectively bricking safe orchestration. A recommended solution is to verify that `newRootSafe` has agreed to be a root safe for the organization, potentially using a state variable and corresponding method to manage this agreement.


  **Link**: [Issue #50](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/50)


- **Potential Logical Inconsistencies in `addSafe` Function Due to Missing State Check**

  The `addSafe` function lacks a check to determine if the `superSafeId` provided is in a removed state. This could allow a removed safe ID to be incorrectly set as a `superSafeId`, leading to logical inconsistencies and potential security issues within the hierarchical structure of safes. Removed safes should not be reassigned as `superSafeId`. The proposed solution involves adding a check to ensure that `superSafeId` is not in a removed state before proceeding with adding a new safe. There are differing opinions on the validity of this concern, as some believe the issue does not exist since the `addSafe` function verifies if the `superSafeId` is already registered and reverts accordingly.


  **Link**: [Issue #52](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/52)


- **Potential Denial of Service in `_exitSafe` Function Due to Module Disabling**

  The `_exitSafe` function includes a check for `getPreviewModule(caller)` and reverts if it returns `address(0)`, which can lead to a Denial of Service (DoS) issue. This occurs because users can call the `disableModule` function on their own, causing subsequent calls to `_exitSafe` to fail. This vulnerability impacts the `removeWholeTree` and `disconnectSafe` functions, and if `disableModule` has been called by the user, it will result in a failure of `_exitSafe`, preventing the proper execution of these critical functions and potentially leading to Protocol insolvency. Mitigation includes updating `_exitSafe` to handle cases where `prevModule` is `address(0)` to avoid unnecessary reversion and ensure continuation even if the module has already been disabled.


  **Link**: [Issue #55](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/55)


- **Root Safe Does Not Call disableSafeLeadRoles in removeWholeTree Function**

  In the `removeWholeTree` function, the `disableSafeLeadRoles` function is called for all safes except the root safe. This can result in issues if the root safe becomes a member of another organization, leading to unexpected behavior and potential security risks as the root safe retains roles it should have been disabled. It's suggested to call `disableSafeLeadRoles` for the root safe to mitigate this. However, it's argued that the root safe is effectively removed by the `_exitSafe(rootSafe)` function at the end, which calls `removeIndexSafe` and deletes the safe from the organization, rendering the issue invalid. The debate remains whether the omission of `disableSafeLeadRoles` specifically hinders proper removal of the root safe's roles.


  **Link**: [Issue #72](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/72)

## Low severity issues


- **Incorrect PALMERA_TX_TYPEHASH Calculation in Constants Contract Breaking EIP-721**

  The `PALMERA_TX_TYPEHASH` constant in the `Constants` contract is incorrectly calculated, breaking EIP-712. As a result, encoded transaction data for Palmera transactions are produced incorrectly, causing transaction hashes to be returned incorrectly and making signature verification non-compliant. This requires a manual fix for correct interoperability.


  **Link**: [Issue #1](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/1)


- **Enum.Type Cannot Be Used in EIP-712 Hash Leading to Incorrect Hash Calculation**

  The description highlights a problem with the use of `Enum.Operation` in EIP-712 hashing. Enums are derived from `uint`, and using them directly in hashing could result in incorrect hashes. It is recommended to use `uint8` instead. There's some debate about its severity and relevance to core contracts.


  **Link**: [Issue #11](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/11)


- **Replace Deprecated `this` with `address(this)` in domainSeparator Function**

  In `Helpers.sol`, the `domainSeparator()` function uses the deprecated `this` keyword. Although the contracts use Solidity 0.8.23, it's recommended to replace `this` with `address(this)` to prevent unexpected behavior. The proposed fix involves updating the code to align with best practices and avoid deprecated variables.


  **Link**: [Issue #28](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/28)


- **Delegatecall Vulnerability in execTransactionOnBehalf Function Allows Safe Destruction**

  The `execTransactionOnBehalf` function in the `PalmeraModule` contract has a vulnerability when executing transactions using the `DelegateCall` operation. If the `to` address is a malicious contract, it can execute a selfdestruct operation, causing the targetSafe contract to be destroyed. This can disrupt the organization by breaking contract modules and halting all transactions.


  **Link**: [Issue #61](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/61)


- **Root Safe Not Revoking Super Safe Role During `removeWholeTree()` Operation**

  After a root safe is removed from an organization, its roles should be revoked. However, if a root safe previously promoted from a super safe still retains the super safe role, this role is not revoked during removal. Consequently, if the safe joins a new organization, it unfairly retains the super safe role without any children. The correct solution is to revoke the super safe role before the root safe exits.


  **Link**: [Issue #92](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/92)



## Conclusion

The Hats.finance audit competition for Palmera, which lasted two weeks, uncovered critical and moderate vulnerabilities. During this public audit, 30 participants shared $30,030 from a $30,030 reward pool. The audit's scope included multiple smart contract files but excluded test, script, and library directories. Notable findings included issues such as bypassing the `isSafe` check, enabling non-safe contracts to misuse functions, and logical inconsistencies that could cause DoS attacks. Recommended fixes include tighter contract checks and enhanced state handling. Several low severity issues, like EIP-712 non-compliance and improper use of delegatecall, also emerged. Hats.finance’s audit competition proved successful in identifying vulnerabilities efficiently and affordably by leveraging a decentralized, results-driven approach, aligning with its mission to achieve robust decentralized security for Web3 projects.

## Disclaimer


This report does not assert that the audited contracts are completely secure. Continuous review and comprehensive testing are advised before deploying critical smart contracts.


The Palmera audit competition illustrates the collaborative effort in identifying and rectifying potential vulnerabilities, enhancing the overall security and functionality of the platform.


Hats.finance does not provide any guarantee or warranty regarding the security of this project. Smart contract software should be used at the sole risk and responsibility of users.

