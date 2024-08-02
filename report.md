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
- Maximum Reward: $30,060
- Submissions: 101
- Total Payout: $30,060 distributed among 30 participants.

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


- **Users Can Bypass `isSafe()` Checks Because of Inadequate Verification**

  A vulnerability has been identified where a user can create a custom contract that returns `1` on `getThreshold()` calls, allowing them to utilize the `PalmeraModule` functionality improperly. This bypasses `isSafe()` checks, enabling non-safe contracts to register organizations, create root safes, and be added as safes through the `addSafe()` function.

To address this, stricter checks are recommended, such as employing `ERC165` `supportsInterface()` checks, rather than solely verifying if `safe` is a contract and checking its `threshold` in `isSafe()`. This would help prevent unauthorized access and functionality manipulation typically reserved for safe contracts. Additionally, such a safe can disrupt various transactions and ownership management functions, making it challenging to manage or disconnect safely.


  **Link**: [Issue #24](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/24)


- **Exploit Allows Malicious Organizations to Disrupt Safe Creation and Orchestration**

  When creating a rootSafe for an organization, the current system only checks if the calling address is a valid root safe, and if the provided address is a safe. However, a user can supply any `newRootSafe` address without ensuring they are related to it. This poses a significant issue because once a `newRootSafe` is added, it cannot be reused by another organization. An exploiter can weaponize this by executing a denial-of-service (DoS) attack, preventing the proper orchestration of safes within the Palmera module. For example, a malicious organization can front-run the `addSafe` function, causing honest transactions to revert because the safe would already be registered. The suggested solution is to ensure `newRootSafe` has agreed to be designated as such for the given organization through additional verification mechanisms.


  **Link**: [Issue #50](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/50)


- **addSafe Function Fails to Check Removed State of superSafeId**

  A potential logical inconsistency in the `addSafe` function was raised, highlighting that the function does not validate if the `superSafeId` provided is in a "removed state." This could lead to a removed safe ID being improperly set as a `superSafeId`, compromising the hierarchical integrity and possibly causing security issues. The issue also applies to the `updateSuper` function, which similarly lacks this validation. 

A proposed mitigation is to incorporate a check ensuring that the `superSafeId` is not in a removed state before adding a new safe. 

While some argue that the contract doesn't have a concept of a "removed state," others insist the issue is valid and needs verification to maintain the integrity of the safe hierarchy.


  **Link**: [Issue #52](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/52)


- **Denial of Service Issue in `_exitSafe` Due to Inadequate `disableModule` Handling**

  The `_exitSafe` function includes a check for `getPreviewModule(caller)` and reverts if it returns `address(0)`, leading to a potential Denial of Service (DoS) vulnerability. Users can call `disableModule` on their own, causing subsequent calls to `_exitSafe` to fail. This flaw affects the `removeWholeTree` and `disconnectSafe` functions. If `disableModule` has been invoked by the user, `_exitSafe` fails and disrupts these functions, potentially causing Protocol insolvency.

To reproduce the issue, a test case was suggested involving the function `test_test`. The proposed solution is to modify `_exitSafe` to handle cases where `prevModule` equals `address(0)`, ensuring the function proceeds without reverting unnecessarily. The debate continues on whether this issue and the provided mitigation correctly address the concern, with some arguing the function should rightfully revert.


  **Link**: [Issue #55](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/55)


- **Conflict Over Root Safe Disabling in removeWholeTree Function**

  In the `removeWholeTree` function, there is a missing call to `disableSafeLeadRoles` for the root safe, unlike the other safes where this function is correctly invoked. This oversight can cause issues if the root safe joins another organization, potentially leading to unexpected behavior and security vulnerabilities due to retained roles that should have been disabled. To address this, the suggested fix involves modifying the code to include a call to `disableSafeLeadRoles` for the root safe as well. However, there is a debate: some argue that the current implementation, which calls `_exitSafe` for the root safe, sufficient removes it, rendering the reported issue invalid. Further verification and testing are needed to confirm the correct behavior.


  **Link**: [Issue #72](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/72)

## Low severity issues


- **Incorrect Calculation of `PALMERA_TX_TYPEHASH` in Constants Contract**

  The constant `PALMERA_TX_TYPEHASH` in the contract **Constants** has been incorrectly calculated, breaking compliance with [EIP-721](https://eips.ethereum.org/EIPS/eip-712). The correct `keccak256` hash should be `0x33d86b91ace2c23c833e6a968f94ce2cdabd89ed7375f3d2135aa0f5a9c131b5` instead of the current incorrect value.


  **Link**: [Issue #1](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/1)


- **Incorrect Use of Enum.Operation in EIP-712 Hash Calculation**

  Enum.Operation is not a standard type and should not be used in EIP-712 hashes. Instead, uint should be used because enums are derived from uint. Using Enum.Operation will result in an incorrect hash. A proof of concept demonstrates this through a provided function.


  **Link**: [Issue #11](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/11)


- **Replace deprecated `this` with `address(this)` in domainSeparator function**

  In `Helpers.sol`, the `domainSeparator()` function uses the deprecated `this` keyword, which can lead to unexpected behavior in Solidity version 0.8.23. It is recommended to replace `this` with `address(this)` to avoid issues and use current best practices.


  **Link**: [Issue #28](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/28)


- **Vulnerability in `execTransactionOnBehalf` Function Allows Destruction of `targetSafe` Contract**

  The `execTransactionOnBehalf` function in the `PalmeraModule` contract allows specific roles to execute transactions. However, if the `to` address in the transaction is malicious, it can exploit the function using a `delegatecall` to execute a `selfdestruct` operation. This can lead to the destruction of the `targetSafe` contract, disrupting the organization by breaking contract modules and halting transactions. To mitigate this, additional checks should be added to verify that the `to` address is not malicious, specifically avoiding the use of `delegatecall` with untrusted addresses.


  **Link**: [Issue #61](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/61)


- **Issue with Promoting and Removing Root Safes without Revoking Super Safe Role**

  There is a design oversight where the super safe role of a root safe is not being revoked upon removal, leading to potential security issues. After the entire tree of safes is removed, a promoted safe retains its super safe role, which could be exploited when re-added to a new organization. The correct fix suggested is to revoke the super safe role before exiting.


  **Link**: [Issue #92](https://github.com/hats-finance/Palmera-0x5fee7541ddcd51ba9f4af606f87b2c42eea655be/issues/92)



## Conclusion

The Hats.finance audit competition on Palmera identified several medium and low-severity security issues that need resolution to secure the protocol effectively. Among the key medium-severity issues were vulnerabilities allowing users to bypass safety checks, execute denial-of-service (DoS) attacks, and misuse removed states in the safe hierarchy. Other significant problems involved handling of the `disableModule` function, which could lead to a DoS, and inadequate role disabling that could compromise security when safes join different organizations. Low-severity issues included incorrect hash calculations, improper use of enumerations in EIP-712, deprecated keyword usage, potential contract destruction through malicious delegate calls, and oversight in revoking roles for root safes. The Palmera audit competition, employing decentralized methods with rewards based on vulnerability identification, proved to be effective, culminating in a total payout of $30,060. The competition underscores the importance of thorough and innovative security audits in fostering a safer Web3 ecosystem.

## Disclaimer


This report does not assert that the audited contracts are completely secure. Continuous review and comprehensive testing are advised before deploying critical smart contracts.


The Palmera audit competition illustrates the collaborative effort in identifying and rectifying potential vulnerabilities, enhancing the overall security and functionality of the platform.


Hats.finance does not provide any guarantee or warranty regarding the security of this project. Smart contract software should be used at the sole risk and responsibility of users.

