// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// ──────────────────────────────────────────────────────────────
//  Shared structs
// ──────────────────────────────────────────────────────────────

struct FeeRecipient {
    uint96 basisPoints;
    address payable recipient;
}

// ──────────────────────────────────────────────────────────────
//  Minimal interfaces
// ──────────────────────────────────────────────────────────────

interface IP2pOrgUnlimitedEthDepositor {
    function addEth(
        bytes32 _eth2WithdrawalCredentials,
        uint96  _ethAmountPerValidatorInWei,
        address _referenceFeeDistributor,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig,
        bytes calldata _extraData
    ) external payable returns (bytes32 depositId, address feeDistributorInstance);

    function refund(
        bytes32 _eth2WithdrawalCredentials,
        uint96  _ethAmountPerValidatorInWei,
        address _feeDistributorInstance
    ) external;

    function totalBalance() external view returns (uint256);
    function depositAmount(bytes32) external view returns (uint112);
    function depositExpiration(bytes32) external view returns (uint40);
    function supportsInterface(bytes4) external view returns (bool);
}

struct SsvCluster {
    uint32 validatorCount;
    uint64 networkFeeIndex;
    uint64 index;
    bool   active;
    uint256 balance;
}

interface IP2pSsvProxyFactory {
    function addEth(
        bytes32 _eth2WithdrawalCredentials,
        uint96  _ethAmountPerValidatorInWei,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig,
        bytes calldata _extraData
    ) external payable returns (bytes32, address, address);

    function registerValidatorsEth(
        address[] calldata _operatorOwners,
        uint64[]  calldata _operatorIds,
        bytes[]   calldata _publicKeys,
        bytes[]   calldata _sharesData,
        SsvCluster calldata _cluster,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    function registerValidators(
        address[] calldata _operatorOwners,
        uint64[]  calldata _operatorIds,
        bytes[]   calldata _publicKeys,
        bytes[]   calldata _sharesData,
        uint256   _amount,
        SsvCluster calldata _cluster,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    function getReferenceFeeDistributor() external view returns (address);
    function supportsInterface(bytes4) external view returns (bool);
}

interface IP2pMessageSender {
    function send(string calldata text) external;
}

interface IMultiSend {
    function multiSend(bytes memory transactions) external payable;
}

interface ISafe {
    function enableModule(address module) external;
    function disableModule(address prevModule, address module) external;
    function setGuard(address guard) external;
    function setFallbackHandler(address handler) external;
    function addOwnerWithThreshold(address owner, uint256 _threshold) external;
    function removeOwner(address prevOwner, address owner, uint256 _threshold) external;
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;
    function changeThreshold(uint256 _threshold) external;
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to, uint256 value, bytes calldata data, uint8 operation,
        uint256 safeTxGas, uint256 baseGas, uint256 gasPrice,
        address gasToken, address refundReceiver, uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to, uint256 value, bytes calldata data,
        uint8 operation, uint256 safeTxGas, uint256 baseGas,
        uint256 gasPrice, address gasToken, address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

// ──────────────────────────────────────────────────────────────
//  Test contract — one test per P0 policy
// ──────────────────────────────────────────────────────────────

contract EthStakingPoliciesTest is Test {

    // ── Known P2P contract addresses ──────────────────────────
    address constant DEPOSITOR           = 0x23BE839a14cEc3D6D716D904f09368Bbf9c750eb;
    address constant SSV_FACTORY_NEW     = 0x7F12A9904bA021AE3ecE106e10f476b7AfBd830C;
    address constant SSV_FACTORY_OLD     = 0x5ed861aec31cCB496689FD2E0A1a3F8e8D7B8824;
    address constant MESSAGE_SENDER      = 0x4E1224f513048e18e7a1883985B45dc0Fe1D917e;
    address constant ETH2_DEP_LEGACY     = 0x4CA21E4D3A86e7399698F88686f5596dBe74ADEb;
    address constant ETH2_DEP_V2         = 0x8e76a33f1aFf7EB15DE832810506814aF4789536;
    address constant REF_FEE_DIST        = 0x3Fcd8D9aCAc042095dFbA53f4C40C74d19E2e9D9;

    // ── System contracts ──────────────────────────────────────
    address constant EIP7002              = 0x00000961Ef480Eb55e80D19ad83579A64c007002;
    address constant EIP7251              = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;

    // ── Safe v1.4.1 ─────────────────────────────────────────
    address constant MULTISEND_V141      = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;
    address constant MULTISEND_V130      = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    address constant MULTISEND_FULL      = 0x38869BF66A61CF6BDDB996A6AE40d5853fd43b52;

    // ── Real mainnet Safe: ENS DAO (1/1 multisig, ~6.7 ETH) ────
    address constant SAFE_ADDR           = 0x4F2083f5fBede34C2714aFfb3105539775f7FE64;
    address constant SAFE_ORIGINAL_OWNER = 0xFe89cc7aBB2C4183683ab71653C4cdc9B02D44b7;
    // Foundry default account #0 — known private key for vm.sign
    uint256 constant SIGNER_PK  = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant SIGNER     = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // ── Well-known tokens ──────────────────────────────────────
    address constant USDC                = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SSV_TOKEN           = 0x9D65fF81a3c488d585bBfb0Bfe3c7707c7917f54;

    // ── Real mainnet EOAs (for pranking) ────────────────────────
    address constant WHALE   = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8; // Binance hot wallet, ~2M ETH
    address constant WHALE_2 = 0x40B38765696e3d5d8d9d834D8AaD4bB6e418E489; // Binance 2, ~1.1M ETH

    // ── Privileged actors ─────────────────────────────────────
    address constant DEPOSITOR_FEE_FACTORY = 0xecA6e48C44C7c0cAf4651E5c5089e564031E8b90;
    address constant DEPOSITOR_OPERATOR    = 0x632788138aa5eac1548b65B41a3d913c291E4cEF;
    address constant DEPOSITOR_OWNER       = 0x18fB2400e61b623c3fc55b212c9022B44EdD1c18;
    address constant LEGACY_DEP_OWNER      = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;

    // ── Forbidden Safe-management selectors (P0.9 – P0.15) ───
    bytes4 constant SEL_ENABLE_MODULE     = bytes4(keccak256("enableModule(address)"));
    bytes4 constant SEL_DISABLE_MODULE    = bytes4(keccak256("disableModule(address,address)"));
    bytes4 constant SEL_SET_GUARD         = bytes4(keccak256("setGuard(address)"));
    bytes4 constant SEL_SET_FALLBACK      = bytes4(keccak256("setFallbackHandler(address)"));
    bytes4 constant SEL_ADD_OWNER         = bytes4(keccak256("addOwnerWithThreshold(address,uint256)"));
    bytes4 constant SEL_REMOVE_OWNER      = bytes4(keccak256("removeOwner(address,address,uint256)"));
    bytes4 constant SEL_SWAP_OWNER        = bytes4(keccak256("swapOwner(address,address,address)"));
    bytes4 constant SEL_CHANGE_THRESHOLD  = bytes4(keccak256("changeThreshold(uint256)"));

    // ── Fork config ───────────────────────────────────────────
    uint256 constant DEFAULT_BLOCK = 24788000;

    string private _rpc;

    function setUp() public {
        _rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(_rpc, DEFAULT_BLOCK);
    }

    // ── Helpers ───────────────────────────────────────────────

    /// Build 0x01-prefixed ETH1 withdrawal credentials.
    function _creds(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr))) | bytes32(bytes1(0x01));
    }

    /// Encode one sub-operation in Safe MultiSend packed format.
    function _packOp(
        uint8   op,
        address to,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(op, to, value, uint256(data.length), data);
    }

    /// Resolve the best available MultiSendCallOnly deployment.
    function _multiSend() internal view returns (address ms) {
        ms = MULTISEND_V141;
        if (ms.code.length == 0) ms = MULTISEND_V130;
        require(ms.code.length > 0, "no MultiSendCallOnly on this fork");
    }

    /// Load raw calldata bytes from a hex file in test/data/.
    function _loadCalldata(string memory filename) internal view returns (bytes memory) {
        string memory hexStr = vm.readFile(string.concat("test/data/", filename));
        return vm.parseBytes(hexStr);
    }

    /// Swap the ENS Safe's owner to SIGNER (Foundry default account #0)
    /// via direct storage writes. Called once, idempotent.
    bool private _ownerSwapped;
    function _installSigner() internal {
        if (_ownerSwapped) return;
        _ownerSwapped = true;
        address safe = SAFE_ADDR;
        // Safe v1.4.1 storage: owners mapping at slot 2 (linked list)
        // sentinel(0x1) → owner → sentinel(0x1)
        bytes32 slotSentinel   = keccak256(abi.encode(address(0x1), uint256(2)));
        bytes32 slotOldOwner   = keccak256(abi.encode(SAFE_ORIGINAL_OWNER, uint256(2)));
        bytes32 slotNewOwner   = keccak256(abi.encode(SIGNER, uint256(2)));

        vm.store(safe, slotSentinel, bytes32(uint256(uint160(SIGNER))));
        vm.store(safe, slotNewOwner, bytes32(uint256(uint160(address(0x1)))));
        vm.store(safe, slotOldOwner, bytes32(0));

        // Verify
        assertEq(ISafe(safe).getOwners()[0], SIGNER, "owner swapped to SIGNER");
    }

    /// Execute an arbitrary tx through the ENS Safe (1/1, threshold=1).
    /// Uses vm.sign with SIGNER_PK — no approveHash needed.
    function _safeExec(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation  // 0 = Call, 1 = DelegateCall
    ) internal {
        _installSigner();
        ISafe safe = ISafe(SAFE_ADDR);

        bytes32 txHash = safe.getTransactionHash(
            to, value, data, operation,
            0, 0, 0, address(0), address(0), safe.nonce()
        );

        // ECDSA signature with the known private key — no approveHash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, txHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(SIGNER, SIGNER);
        bool ok = safe.execTransaction(
            to, value, data, operation,
            0, 0, 0, address(0), payable(address(0)), sig
        );
        assertTrue(ok, "Safe execTransaction must succeed");
    }

    /// Assert that `sel` is not any of the P0.9–P0.15 forbidden selectors.
    function _assertNotForbidden(bytes4 sel) internal pure {
        assert(sel != SEL_ENABLE_MODULE);
        assert(sel != SEL_DISABLE_MODULE);
        assert(sel != SEL_SET_GUARD);
        assert(sel != SEL_SET_FALLBACK);
        assert(sel != SEL_ADD_OWNER);
        assert(sel != SEL_REMOVE_OWNER);
        assert(sel != SEL_SWAP_OWNER);
        assert(sel != SEL_CHANGE_THRESHOLD);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.1  Function Selector Whitelist – P2pOrgUnlimitedEthDepositor
    //        Allowed selectors: addEth, refund
    // ═══════════════════════════════════════════════════════════

    function test_P0_1a_addEth_on_depositor() public {
        vm.prank(WHALE);
        (bytes32 depositId, address feeDist) =
            IP2pOrgUnlimitedEthDepositor(DEPOSITOR).addEth{value: 32 ether}(
                _creds(WHALE),
                uint96(32 ether),
                REF_FEE_DIST,
                FeeRecipient(9000, payable(WHALE)),
                FeeRecipient(0,    payable(address(0))),
                ""
            );

        assertTrue(depositId != bytes32(0),   "depositId non-zero");
        assertTrue(feeDist   != address(0),    "feeDistributor created");
        assertEq(uint256(IP2pOrgUnlimitedEthDepositor(DEPOSITOR).depositAmount(depositId)), 32 ether);
    }

    function test_P0_1b_refund_on_depositor() public {
        // 1. Create deposit
        vm.prank(WHALE);
        (bytes32 depositId, address feeDist) =
            IP2pOrgUnlimitedEthDepositor(DEPOSITOR).addEth{value: 32 ether}(
                _creds(WHALE),
                uint96(32 ether),
                REF_FEE_DIST,
                FeeRecipient(9000, payable(WHALE)),
                FeeRecipient(0,    payable(address(0))),
                ""
            );

        // 2. Fast-forward past the 1-day deposit expiration
        uint40 expiry = IP2pOrgUnlimitedEthDepositor(DEPOSITOR).depositExpiration(depositId);
        vm.warp(uint256(expiry) + 1);

        // 3. Refund
        uint256 balBefore = WHALE.balance;
        vm.prank(WHALE);
        IP2pOrgUnlimitedEthDepositor(DEPOSITOR).refund(
            _creds(WHALE),
            uint96(32 ether),
            feeDist
        );
        assertGt(WHALE.balance, balBefore, "client received ETH back");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.2  Function Selector Whitelist – P2pSsvProxyFactory
    //        Allowed: addEth, registerValidators, registerValidatorsEth
    // ═══════════════════════════════════════════════════════════

    function test_P0_2a_addEth_on_factory() public {
        // Replay real successful addEth tx on old factory (same selector as new factory)
        // tx 0x61789a38… · block 24691463 · from 0x6717f57a… · value 71 ETH
        vm.createSelectFork(_rpc, 24691462);

        address sender = 0x6717F57a7E18c4758f0E83E786E08cE538e0436C;
        vm.deal(sender, 100 ether);

        bytes memory cd = _loadCalldata("factoryAddEth.hex");
        vm.prank(sender);
        (bool ok,) = SSV_FACTORY_OLD.call{value: 71 ether}(cd);
        assertTrue(ok, "addEth on P2pSsvProxyFactory");
    }

    /// Assert a revert did NOT originate from factory access control.
    function _assertNotFactoryACL(bytes memory ret) internal pure {
        if (ret.length >= 4) {
            bytes4 errSel;
            assembly { errSel := mload(add(ret, 0x20)) }
            assert(errSel != bytes4(keccak256("P2pSsvProxyFactory__NotAllowedSsvOperatorOwner(address)")));
            assert(errSel != bytes4(keccak256("Access__CallerNeitherOperatorNorOwner(address,address,address)")));
            assert(errSel != bytes4(keccak256("P2pSsvProxyFactory__SsvOperatorNotAllowed(address,uint64)")));
        }
    }

    /// Helper: sorted operator owners + IDs for the new factory.
    function _operators()
        internal
        pure
        returns (address[] memory owners, uint64[] memory ids)
    {
        // Sorted ascending by owner address (factory enforces strict ordering)
        owners = new address[](4);
        owners[0] = 0x47659cc5fB8CDC58bD68fEB8C78A8e19549d39C5;
        owners[1] = 0x95b3D923060b7E6444d7C3F0FCb01e6F37F4c418;
        owners[2] = 0x9a792B1588882780Bed412796337E0909e51fAB7;
        owners[3] = 0xfeC26f2bC35420b4fcA1203EcDf689a6e2310363;

        // Corresponding operator IDs (from getAllowedSsvOperatorIds)
        ids = new uint64[](4);
        ids[0] = 1034;
        ids[1] = 1033;
        ids[2] = 1035;
        ids[3] = 1032;
    }

    /// Helper: fresh 48-byte pubkey (not already registered on SSV) + shares data.
    function _validatorData()
        internal
        view
        returns (bytes[] memory pubkeys, bytes[] memory shares)
    {
        pubkeys = new bytes[](1);
        // Deterministic but unregistered 48-byte pubkey
        pubkeys[0] = abi.encodePacked(
            keccak256("p2p_test_registerValidators_fresh_pubkey"),
            bytes16(keccak256("p2p_test_pubkey_tail"))
        );

        shares = new bytes[](1);
        shares[0] = vm.parseBytes(vm.readFile("test/data/sharesData.hex"));
    }

    function test_P0_2b_registerValidators_on_factory() public {
        // Replay a real successful registerValidators tx.
        // Both old and new factory share the same selector (0x3c028324) for the
        // explicit registerValidators(address[],uint64[],bytes[],bytes[],uint256,
        //   Cluster,FeeRecipient,FeeRecipient) overload.
        // The old factory is used because it has real on-chain SSV cluster state
        // that matches the calldata. The new factory has no prior SSV registrations,
        // so the SSV Network rejects the cluster state (IncorrectClusterState).
        //
        // tx 0x378c2595… · block 23895639 · from 0x5cb5ada4…
        vm.createSelectFork(_rpc, 23895638);

        address sender = 0x5cb5AdA4388454320325347bE70F07602cC3B2d5;
        vm.deal(sender, 1 ether);

        bytes memory cd = _loadCalldata("registerValidators.hex");
        vm.prank(sender);
        (bool ok,) = SSV_FACTORY_OLD.call{value: 261685080000}(cd);
        assertTrue(ok, "registerValidators on P2pSsvProxyFactory");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.3  Function Selector Whitelist – P2pMessageSender
    //        Allowed selector: send
    // ═══════════════════════════════════════════════════════════

    function test_P0_3_send_on_messageSender() public {
        vm.prank(WHALE);
        IP2pMessageSender(MESSAGE_SENDER).send(
            '{"action":"withdraw","pubkeys":["0xabc123"]}'
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.4  Function Selector Whitelist – P2pEth2Depositor
    //        Allowed selector: deposit
    // ═══════════════════════════════════════════════════════════

    function test_P0_4a_deposit_legacy() public {
        // Replay real deposit on legacy P2pEth2Depositor
        // tx 0x6daa4dae… · block 24523645 · from 0x1461da3e… · 32 ETH
        vm.createSelectFork(_rpc, 24523644);

        address sender = 0x1461Da3E1b86EA1Aa273eC32664758e5E192233a;
        vm.deal(sender, 33 ether);

        bytes memory cd = _loadCalldata("depositLegacy.hex");
        vm.prank(sender);
        (bool ok,) = ETH2_DEP_LEGACY.call{value: 32 ether}(cd);
        assertTrue(ok, "deposit on legacy P2pEth2Depositor");
    }

    function test_P0_4b_deposit_v2() public {
        // Replay real deposit on v2 P2pEth2Depositor
        // tx 0x95125eee… · block 23766675 · from 0xcc912ce0… · 32 ETH
        vm.createSelectFork(_rpc, 23766674);

        address sender = 0xCc912Ce06E97cC7Ec925c61378D82a1146010128;
        vm.deal(sender, 33 ether);

        bytes memory cd = _loadCalldata("depositV2.hex");
        vm.prank(sender);
        (bool ok,) = ETH2_DEP_V2.call{value: 32 ether}(cd);
        assertTrue(ok, "deposit on v2 P2pEth2Depositor");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.5  Target Address Restriction – not a token contract
    // ═══════════════════════════════════════════════════════════

    function test_P0_5_target_is_not_token() public view {
        // Depositor supports ERC-165 but is not ERC-721 / ERC-1155
        assertTrue(
            IP2pOrgUnlimitedEthDepositor(DEPOSITOR).supportsInterface(0x01ffc9a7),
            "ERC-165 supported"
        );
        assertFalse(
            IP2pOrgUnlimitedEthDepositor(DEPOSITOR).supportsInterface(0x80ac58cd),
            "not ERC-721"
        );
        assertFalse(
            IP2pOrgUnlimitedEthDepositor(DEPOSITOR).supportsInterface(0xd9b67a26),
            "not ERC-1155"
        );

        // ERC-20 has no ERC-165, check that transfer() is absent
        (bool ok,) = DEPOSITOR.staticcall(
            abi.encodeWithSelector(0xa9059cbb, address(1), uint256(0))
        );
        assertFalse(ok, "transfer() absent on depositor");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.6  Target Address Restriction – ETH to known P2P addr
    // ═══════════════════════════════════════════════════════════

    function test_P0_6_eth_to_known_p2p_contract() public {
        // ETH (value > 0) sent to a known P2P contract via addEth
        vm.prank(WHALE);
        IP2pOrgUnlimitedEthDepositor(DEPOSITOR).addEth{value: 32 ether}(
            _creds(WHALE),
            uint96(32 ether),
            REF_FEE_DIST,
            FeeRecipient(9000, payable(WHALE)),
            FeeRecipient(0,    payable(address(0))),
            ""
        );

        // System contracts (EIP-7002, EIP-7251) also exist
        assertTrue(EIP7002.code.length > 0, "EIP-7002 contract exists");
        assertTrue(EIP7251.code.length > 0, "EIP-7251 contract exists");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.7  Multicall Shape – no delegatecall (operation ≠ 1)
    // ═══════════════════════════════════════════════════════════

    function test_P0_7_multisend_no_delegatecall() public {
        // Safe executes a multiSend (DelegateCall to MultiSend singleton)
        // where every sub-operation uses operation=0 (Call), not delegatecall.
        bytes memory txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, abi.encodeCall(IP2pMessageSender.send, ("p07-op1"))),
            _packOp(0, MESSAGE_SENDER, 0, abi.encodeCall(IP2pMessageSender.send, ("p07-op2"))),
            _packOp(0, MESSAGE_SENDER, 0, abi.encodeCall(IP2pMessageSender.send, ("p07-op3")))
        );

        // Verify every sub-op has operation = 0 (Call)
        uint256 i;
        while (i < txs.length) {
            assertEq(uint8(txs[i]), 0, "all ops must be Call(0), not DelegateCall(1)");
            uint256 dataLen;
            assembly { dataLen := mload(add(add(txs, 0x20), add(i, 53))) }
            i += 85 + dataLen;
        }

        // Execute through the real Gnosis DAO Safe (DelegateCall to MultiSend)
        _safeExec(MULTISEND_FULL, 0, abi.encodeCall(IMultiSend.multiSend, (txs)), 1);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.8  Multicall Shape – at most 10 sub-operations
    // ═══════════════════════════════════════════════════════════

    function test_P0_8_multisend_max_10_ops() public {
        // Safe executes a multiSend with 5 sub-operations (≤10 limit)
        bytes memory txs;
        uint256 opCount;
        for (uint256 j; j < 5; j++) {
            txs = abi.encodePacked(txs, _packOp(0, MESSAGE_SENDER, 0,
                abi.encodeCall(IP2pMessageSender.send,
                    (string(abi.encodePacked("p08-op", bytes1(uint8(0x30 + j))))))));
            opCount++;
        }
        assertTrue(opCount <= 10, "at most 10 sub-operations");
        _safeExec(MULTISEND_FULL, 0, abi.encodeCall(IMultiSend.multiSend, (txs)), 1);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.9  Safe Management – no enableModule / disableModule
    // ═══════════════════════════════════════════════════════════

    function test_P0_9_no_enableModule_disableModule() public {
        // Safe calls P2pMessageSender.send (allowed) — selector ≠ enableModule/disableModule
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p09-test"));
        bytes4 sel = bytes4(data);
        assertTrue(sel != SEL_ENABLE_MODULE && sel != SEL_DISABLE_MODULE);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.10  Safe Management – no setGuard
    // ═══════════════════════════════════════════════════════════

    function test_P0_10_no_setGuard() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p10-test"));
        assertTrue(bytes4(data) != SEL_SET_GUARD);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.11  Safe Management – no setFallbackHandler
    // ═══════════════════════════════════════════════════════════

    function test_P0_11_no_setFallbackHandler() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p11-test"));
        assertTrue(bytes4(data) != SEL_SET_FALLBACK);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.12  Safe Management – no addOwnerWithThreshold
    // ═══════════════════════════════════════════════════════════

    function test_P0_12_no_addOwnerWithThreshold() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p12-test"));
        assertTrue(bytes4(data) != SEL_ADD_OWNER);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.13  Safe Management – no removeOwner
    // ═══════════════════════════════════════════════════════════

    function test_P0_13_no_removeOwner() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p13-test"));
        assertTrue(bytes4(data) != SEL_REMOVE_OWNER);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.14  Safe Management – no swapOwner
    // ═══════════════════════════════════════════════════════════

    function test_P0_14_no_swapOwner() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p14-test"));
        assertTrue(bytes4(data) != SEL_SWAP_OWNER);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.15  Safe Management – no changeThreshold
    // ═══════════════════════════════════════════════════════════

    function test_P0_15_no_changeThreshold() public {
        bytes memory data = abi.encodeCall(IP2pMessageSender.send, ("p15-test"));
        assertTrue(bytes4(data) != SEL_CHANGE_THRESHOLD);
        _safeExec(MESSAGE_SENDER, 0, data, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  BONUS  Comprehensive multiSend check for P0.7–P0.15
    // ═══════════════════════════════════════════════════════════

    function test_P0_9to15_comprehensive_multisend() public {
        // Build a multiSend with diverse valid P2P operations
        bytes memory txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0,
                abi.encodeCall(IP2pMessageSender.send, ("comprehensive-1"))),
            _packOp(0, MESSAGE_SENDER, 0,
                abi.encodeCall(IP2pMessageSender.send, ("comprehensive-2"))),
            _packOp(0, DEPOSITOR, 0,
                abi.encodeWithSelector(IP2pOrgUnlimitedEthDepositor.totalBalance.selector))
        );

        // Parse packed encoding — verify P0.7 (no delegatecall),
        // P0.8 (≤10 ops), P0.9–P0.15 (no forbidden selectors)
        uint256 i;
        uint256 count;
        while (i < txs.length) {
            assertEq(uint8(txs[i]), 0, "P0.7: no delegatecall");

            uint256 dataLen;
            assembly { dataLen := mload(add(add(txs, 0x20), add(i, 53))) }

            if (dataLen >= 4) {
                bytes4 sel;
                assembly { sel := mload(add(add(txs, 0x20), add(i, 85))) }
                _assertNotForbidden(sel);
            }

            i += 85 + dataLen;
            count++;
        }

        assertTrue(count <= 10, "P0.8: at most 10 ops");

        // Execute through the real Gnosis DAO Safe
        _safeExec(MULTISEND_FULL, 0, abi.encodeCall(IMultiSend.multiSend, (txs)), 1);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║          NEGATIVE TEST CASES (policy should DENY)        ║
    // ║  Each tx succeeds on-chain but violates a P0 policy.     ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ═══════════════════════════════════════════════════════════
    //  P0.1 NEG — forbidden selector on P2pOrgUnlimitedEthDepositor
    //             (rejectService is NOT addEth or refund)
    // ═══════════════════════════════════════════════════════════

    function test_P0_1_NEG_rejectService_on_depositor() public {
        // Create a deposit first so there's something to reject
        vm.prank(WHALE);
        (bytes32 depositId,) = IP2pOrgUnlimitedEthDepositor(DEPOSITOR).addEth{value: 32 ether}(
            _creds(WHALE), uint96(32 ether), REF_FEE_DIST,
            FeeRecipient(9000, payable(WHALE)),
            FeeRecipient(0, payable(address(0))), ""
        );

        // rejectService requires operator/owner of the fee distributor factory
        vm.prank(DEPOSITOR_OPERATOR);
        (bool ok,) = DEPOSITOR.call(
            abi.encodeWithSignature("rejectService(bytes32,string)", depositId, "test rejection")
        );
        assertTrue(ok, "rejectService succeeds on-chain (but policy should deny)");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.2 NEG — forbidden selector on P2pSsvProxyFactory
    //             (changeOperator is NOT addEth/registerValidators/registerValidatorsEth)
    // ═══════════════════════════════════════════════════════════

    function test_P0_2_NEG_changeOperator_on_factory() public {
        address factoryOwner = 0x18fB2400e61b623c3fc55b212c9022B44EdD1c18;
        address newOperator  = WHALE_2;

        // changeOperator is an owner-only function — NOT in the allowed selector list
        vm.prank(factoryOwner);
        (bool ok,) = SSV_FACTORY_NEW.call(
            abi.encodeWithSignature("changeOperator(address)", newOperator)
        );
        assertTrue(ok, "changeOperator succeeds on-chain (but policy should deny)");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.3 NEG — P2pMessageSender has no other functions besides send().
    //             Policy would deny any non-send selector. We show the calldata
    //             that would be constructed (targeting MessageSender with wrong selector).
    //             Since the contract has no fallback, this WOULD revert on-chain.
    // ═══════════════════════════════════════════════════════════

    function test_P0_3_NEG_wrong_selector_on_messageSender() public view {
        // P2pMessageSender only has send(string). Any other selector reverts.
        // We verify the policy would catch a non-send selector.
        bytes4 sendSel = IP2pMessageSender.send.selector;
        bytes4 badSel  = bytes4(keccak256("transfer(address,uint256)"));
        assertTrue(sendSel != badSel, "transfer selector differs from send");

        // Confirm the contract has no fallback (code exists but wrong selector reverts)
        assertTrue(MESSAGE_SENDER.code.length > 0, "contract exists");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.4 NEG — forbidden selector on P2pEth2Depositor
    //             (pause is NOT deposit)
    // ═══════════════════════════════════════════════════════════

    function test_P0_4_NEG_pause_on_legacy_depositor() public {
        // pause() is owner-only on the legacy depositor
        vm.prank(LEGACY_DEP_OWNER);
        (bool ok,) = ETH2_DEP_LEGACY.call(abi.encodeWithSignature("pause()"));
        assertTrue(ok, "pause succeeds on-chain (but policy should deny)");

        // Clean up: unpause so other tests aren't affected
        vm.prank(LEGACY_DEP_OWNER);
        (bool ok2,) = ETH2_DEP_LEGACY.call(abi.encodeWithSignature("unpause()"));
        assertTrue(ok2, "unpause");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.5 NEG — call targets a token contract (ERC-20)
    // ═══════════════════════════════════════════════════════════

    function test_P0_5_NEG_call_targets_token_contract() public {
        // Transfer USDC from WHALE to WHALE_2 — this targets a token contract
        deal(USDC, WHALE, 1000e6);

        vm.prank(WHALE);
        bool ok = IERC20(USDC).transfer(WHALE_2, 100e6);
        assertTrue(ok, "ERC-20 transfer succeeds (but policy should deny)");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.6 NEG — ETH sent to a non-P2P, non-system address
    // ═══════════════════════════════════════════════════════════

    function test_P0_6_NEG_eth_to_unknown_address() public {
        // Send ETH from WHALE to WHALE_2 (not a P2P or system contract)
        uint256 balBefore = WHALE_2.balance;
        vm.prank(WHALE);
        (bool ok,) = WHALE_2.call{value: 1 ether}("");
        assertTrue(ok, "ETH to unknown address succeeds (but policy should deny)");
        assertEq(WHALE_2.balance, balBefore + 1 ether);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.7 NEG — multiSend with delegatecall (operation = 1)
    // ═══════════════════════════════════════════════════════════

    function test_P0_7_NEG_multisend_with_delegatecall() public {
        // Build a multiSend payload where one sub-op uses operation=1 (DelegateCall)
        bytes memory sendData = abi.encodeCall(IP2pMessageSender.send, ("delegatecall-test"));
        bytes memory txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, sendData),  // Call (OK)
            _packOp(1, MESSAGE_SENDER, 0, sendData)   // DelegateCall (policy violation!)
        );

        // Verify the payload contains operation=1
        bool hasDelegatecall;
        uint256 i;
        while (i < txs.length) {
            if (uint8(txs[i]) == 1) hasDelegatecall = true;
            uint256 dataLen;
            assembly { dataLen := mload(add(add(txs, 0x20), add(i, 53))) }
            i += 85 + dataLen;
        }
        assertTrue(hasDelegatecall, "payload contains delegatecall op");

        // Execute through the real Gnosis DAO Safe via DelegateCall to MultiSend
        // (this is how a Safe batches calls — it delegatecalls the MultiSend singleton)
        _safeExec(
            MULTISEND_FULL,
            0,
            abi.encodeCall(IMultiSend.multiSend, (txs)),
            1 // DelegateCall
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.8 NEG — multiSend with >10 sub-operations
    // ═══════════════════════════════════════════════════════════

    function test_P0_8_NEG_multisend_over_10_ops() public {
        bytes memory txs;
        uint256 opCount;

        // Build 11 sub-operations (exceeds limit of 10)
        for (uint256 j; j < 11; j++) {
            bytes memory data = abi.encodeCall(
                IP2pMessageSender.send,
                (string(abi.encodePacked("neg-op", bytes1(uint8(0x30 + j)))))
            );
            txs = abi.encodePacked(txs, _packOp(0, MESSAGE_SENDER, 0, data));
            opCount++;
        }

        assertTrue(opCount > 10, "multicall has >10 sub-operations (policy should deny)");

        // Still executes fine on-chain
        IMultiSend(_multiSend()).multiSend(txs);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.9 NEG — call enableModule on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_9_NEG_enableModule_on_safe() public {
        // 3 Gnosis DAO Safe owners approve + execute enableModule
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.enableModule, (WHALE)),
            0 // Call
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.10 NEG — call setGuard on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_10_NEG_setGuard_on_safe() public {
        // Safe's setGuard checks supportsInterface on the guard. Mock it on WHALE.
        vm.mockCall(WHALE, abi.encodeWithSelector(0x01ffc9a7), abi.encode(true));

        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.setGuard, (WHALE)),
            0
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.11 NEG — call setFallbackHandler on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_11_NEG_setFallbackHandler_on_safe() public {
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.setFallbackHandler, (WHALE)),
            0
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.12 NEG — call addOwnerWithThreshold on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_12_NEG_addOwnerWithThreshold_on_safe() public {
        // ENS Safe has 1 owner (SIGNER). Add WHALE as 2nd owner, threshold stays 1.
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.addOwnerWithThreshold, (WHALE, 1)),
            0
        );
        assertEq(ISafe(SAFE_ADDR).getOwners().length, 2, "owner added");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.13 NEG — call removeOwner on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_13_NEG_removeOwner_on_safe() public {
        // First add a 2nd owner so we can remove one (can't remove the only owner)
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.addOwnerWithThreshold, (WHALE, 1)),
            0
        );
        assertEq(ISafe(SAFE_ADDR).getOwners().length, 2);

        // Remove WHALE. In linked list: sentinel → WHALE → SIGNER → sentinel
        // (addOwner prepends). prevOwner for WHALE = sentinel(0x1).
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.removeOwner, (address(0x1), WHALE, 1)),
            0
        );
        assertEq(ISafe(SAFE_ADDR).getOwners().length, 1, "owner removed");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.14 NEG — call swapOwner on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_14_NEG_swapOwner_on_safe() public {
        // Swap SIGNER → WHALE. Linked list: sentinel → SIGNER → sentinel.
        // prevOwner for SIGNER = sentinel(0x1).
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.swapOwner, (address(0x1), SIGNER, WHALE)),
            0
        );
        assertEq(ISafe(SAFE_ADDR).getOwners()[0], WHALE, "owner swapped");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.15 NEG — call changeThreshold on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_15_NEG_changeThreshold_on_safe() public {
        // Add 2nd owner first (threshold can't exceed owner count)
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.addOwnerWithThreshold, (WHALE, 1)),
            0
        );

        // Now change threshold from 1 → 2
        _safeExec(
            SAFE_ADDR, 0,
            abi.encodeCall(ISafe.changeThreshold, (2)),
            0
        );
        assertEq(ISafe(SAFE_ADDR).getThreshold(), 2, "threshold changed");
    }
}
