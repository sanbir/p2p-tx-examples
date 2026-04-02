# Ethereum (Staking)

Known contracts:


| P2pEth2Depositor (legacy)               | `0x4ca21e4d3a86e7399698f88686f5596dbe74adeb`                                                                                             |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| P2pEth2Depositor (v2)                   | `0x8e76a33f1aFf7EB15DE832810506814aF4789536`                                                                                             |
| P2pOrgUnlimitedEthDepositor             | `0x23BE839a14cEc3D6D716D904f09368Bbf9c750eb`, `0x7c58c03AABf3Cc131903592B40C192BB4F949f1F`, `0xb3C7b1b21189DBCB78F21FBA26208a90ddA7E256` |
| P2pSsvProxyFactory                      | `0x10F4ec919E3e692cB79301E58a7055C783630Dfc`, `0xcb924D4BE3Ff04B2d2116fE116138950373111d9`, `0x5ed861aec31cCB496689FD2E0A1a3F8e8D7B8824` |
| DeoracleizedFeeDistributor (ref)        | `0x3Fcd8D9aCAc042095dFbA53f4C40C74d19E2e9D9`                                                                                             |
| P2pMessageSender                        | `0x4E1224f513048e18e7a1883985B45dc0Fe1D917e`                                                                                             |
| EIP-7002 Withdrawal Request (system)    | `0x00000961Ef480Eb55e80D19ad83579A64c007002`                                                                                             |
| EIP-7251 Consolidation Request (system) | `0x0000BBdDc7CE488642fb579F8B00f3a590007251`                                                                                             |
| FeeDistributor instances                | Per-client clones. Can be verified by code hash (minimal proxy to `0xc4AeD615614f26c8df4eaAf4A1cAEA9184AeB3dE`)                          |
| P2pSsvProxy instances                   | Per-client beacon proxies. Can be verified by checking against `getAllP2pSsvProxies()`of any verified P2pSsvProxyFactory                 |


💡

A call to a contract means any message call — whether external (from an EOA) or internal (contract-to-contract).



## P0 — Static field checks (selector lookup, address lookup, single-field comparison)


| #         | Policy Type                       | Policy Rule                                                                                                                                                          |
| --------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ETH.P0.1  | Function Selector Whitelist       | Deny tx if a call to `P2pOrgUnlimitedEthDepositor` uses a selector other than `addEth` or `refund`                                                                   |
| ETH.P0.2  | Function Selector Whitelist       | Deny tx if a call to `P2pSsvProxyFactory` uses a selector other than `addEth`, `registerValidators`, or `registerValidatorsEth`                                      |
| ETH.P0.3  | Function Selector Whitelist       | Deny tx if a call to `P2pMessageSender` uses a selector other than `send`                                                                                            |
| ETH.P0.4  | Function Selector Whitelist       | Deny tx if a call to `P2pEth2Depositor` (legacy or v2) uses a selector not in the allowed list: `deposit`                                                            |
| ETH.P0.5  | Target Address Restriction        | Deny tx if any decoded call targets a token contract (ERC-20, ERC-721, ERC-1155), regardless of function selector                                                    |
| ETH.P0.6  | Target Address Restriction        | Deny tx if any decoded call sends ETH (value > 0) to an address that is not a known P2P contract or system contract (EIP-7002 `0x0000…7002`, EIP-7251 `0x0000…7251`) |
| ETH.P0.7  | Multicall Shape — Delegatecall    | Deny tx if any sub-operation in a Gnosis Safe `multiSend` has `operation = 1` (delegatecall)                                                                         |
| ETH.P0.8  | Multicall Shape — Operation Count | Deny tx if a multicall contains more than 10 sub-operations                                                                                                          |
| ETH.P0.9  | Safe Management Protection        | Deny tx if any call invokes `enableModule` or `disableModule` on any target, regardless of batching context                                                          |
| ETH.P0.10 | Safe Management Protection        | Deny tx if any call invokes `setGuard` on any target, regardless of batching context                                                                                 |
| ETH.P0.11 | Safe Management Protection        | Deny tx if any call invokes `setFallbackHandler` on any target, regardless of batching context                                                                       |
| ETH.P0.12 | Safe Management Protection        | Deny tx if any call invokes `addOwnerWithThreshold` on any target                                                                                                    |
| ETH.P0.13 | Safe Management Protection        | Deny tx if any call invokes `removeOwner` on any target                                                                                                              |
| ETH.P0.14 | Safe Management Protection        | Deny tx if any call invokes `swapOwner` on any target                                                                                                                |
| ETH.P0.15 | Safe Management Protection        | Deny tx if any call invokes `changeThreshold` on any target                                                                                                          |


## P1 — Decoded-payload logic (multicall parsing, classifying sub-calls, cross-field checks)


| #         | Policy Type                        | Policy Rule                                                                                                                                            |
| --------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ETH.P1.1  | Multicall Shape — Mixed Operations | Deny tx if a multicall contains both calls to P2P contracts and calls to non-P2P contracts                                                             |
| ETH.P1.2  | Multicall Shape — Self-Call        | Deny tx if any inner call within a multicall targets the Safe itself (address(this))                                                                   |
| ETH.P1.3  | Multicall Shape — ETH Value        | Deny tx if total ETH sent across all multicall sub-operations does not equal the sum of expected staking deposit amounts                               |
| ETH.P1.4  | Multicall Shape — ETH Value        | Deny tx if any ETH (value > 0) within a multicall is sent to a non-P2P address                                                                         |
| ETH.P1.5  | Cross-Contract                     | Deny tx if multicall includes calls to flash loan providers (Aave, Balancer, etc.) alongside P2P staking calls                                         |
| ETH.P1.6  | ERC-4337 Validation                | Deny UserOperation if `callData` decodes to a batch containing both P2P staking calls and non-staking calls                                            |
| ETH.P1.7  | ERC-4337 Validation                | Deny UserOperation targeting a FeeDistributor if calldata does not decode to `withdraw()`                                                              |
| ETH.P1.8  | ERC-7702 Validation                | Deny type-4 tx if any entry in `authorization_list` delegates to a non-whitelisted contract address                                                    |
| ETH.P1.9  | Function Selector Whitelist        | Deny tx if a call to EIP-7002 or EIP-7251 has calldata that does not conform to the expected packed entry format                                       |
| ETH.P1.10 | Encoding Integrity                 | Deny tx if calldata contains unexpected trailing bytes beyond the ABI-encoded length                                                                   |
| ETH.P1.11 | Encoding Integrity                 | Deny tx if Gnosis Safe `multiSend` packed encoding has overlapping operations, inconsistent length fields, or hidden operations after the apparent end |


## P2 — Stateful / external-data checks (rate limits, on-chain lookups, risk feeds, contract metadata)


| #         | Policy Type           | Policy Rule                                                                                                                         |
| --------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| ETH.P2.1  | Rate Limit            | Deny tx if cumulative daily ETH deposits from this wallet exceed 1024 ETH                                                           |
| ETH.P2.2  | Rate Limit            | Deny tx if number of validators registered from this wallet in 24h exceeds 5                                                        |
| ETH.P2.3  | Rate Limit            | Deny tx if number of `refund()` calls from this wallet in 24h exceeds 2                                                             |
| ETH.P2.4  | Address / Entity Risk | Deny tx if any address in the call tree is OFAC-sanctioned or flagged by threat intelligence                                        |
| ETH.P2.5  | Address / Entity Risk | Flag or deny tx if any target contract was deployed within the last 7k blocks                                                       |
| ETH.P2.6  | Address / Entity Risk | Deny tx if any target contract within a staking multicall is unverified on Etherscan/Sourcify                                       |
| ETH.P2.7  | ERC-4337 Validation   | Deny UserOperation if `paymasterAndData` references an unknown/untrusted paymaster contract                                         |
| ETH.P2.8  | ERC-4337 Validation   | Deny UserOperation if `initCode` references an unknown/untrusted account factory                                                    |
| ETH.P2.9  | Safe Module Origin    | Deny tx if it originates from an unknown/unaudited Safe module (`execTransactionFromModule`)                                        |
| ETH.P2.10 | Encoding Integrity    | Deny tx if a function selector on a non-P2P contract does not resolve to the expected function name on that contract's verified ABI |
| ETH.P2.11 | ERC-7702 Validation   | Flag tx if an existing ERC-7702 delegation is being revoked mid-staking flow                                                        |


## P3 — Simulation & deep analysis (tx simulation, state diffing, cryptographic verification)


| #        | Policy Type                  | Policy Rule                                                                                                          |
| -------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ETH.P3.1 | Simulation — Balance Delta   | Deny tx if simulated post-execution wallet ETH balance decreases by more than the expected staking amount (plus gas) |
| ETH.P3.2 | Simulation — Token Balance   | Deny tx if simulation shows any ERC-20 token balance of the wallet decreasing                                        |
| ETH.P3.3 | Simulation — Approval State  | Deny tx if simulation shows any new or increased ERC-20 `allowance` for the wallet                                   |
| ETH.P3.4 | Simulation — Ownership State | Deny tx if simulation shows Safe `getOwners()`, `getThreshold()`, or `getModules()` changed post-execution           |
| ETH.P3.5 | Simulation — Revert          | Deny tx if simulation shows the transaction will revert                                                              |
| ETH.P3.6 | Simulation — State Changes   | Flag or deny tx if simulation shows storage changes on contracts outside the expected P2P contract set               |
| ETH.P3.7 | Encoding Integrity           | Deny tx if the EIP-712 signed hash does not correspond to the transaction being presented to the user                |
| ETH.P3.8 | Cross-Contract / Reentrancy  | Flag tx if `_clientConfig.recipient` is a contract with complex `receive()`/`fallback()` logic                       |


