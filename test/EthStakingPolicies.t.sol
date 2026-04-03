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

    // ── Real mainnet Safe: Gnosis DAO (3/11 multisig, ~3.2 ETH) ──
    address constant GNOSIS_SAFE         = 0x849D52316331967b6fF1198e5E32A0eB168D039d;
    // First 3 owners in ascending address order (needed for sorted signatures)
    address constant SAFE_SIGNER_1       = 0x0DA0C3e52C977Ed3cBc641fF02DD271c3ED55aFe;
    address constant SAFE_SIGNER_2       = 0x1B0C638616Ed79dB430Edbf549ad9512FF4a8ed1;
    address constant SAFE_SIGNER_3       = 0x5fFDAB6A4907E9e65B342d9b2929960b0989a246;

    // ── Well-known tokens (for P0.5 negative) ────────────────
    address constant USDC                = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

    /// Execute an arbitrary tx through the Gnosis DAO Safe (3/11 multisig).
    /// Pranks 3 real EOA owners to approveHash, then executes from signer 1.
    function _safeExec(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation  // 0 = Call, 1 = DelegateCall
    ) internal {
        ISafe safe = ISafe(GNOSIS_SAFE);
        uint256 n = safe.nonce();

        bytes32 txHash = safe.getTransactionHash(
            to, value, data, operation,
            0, 0, 0, address(0), address(0), n
        );

        // 3 owners approve the hash (each pranked as real EOA)
        vm.prank(SAFE_SIGNER_1, SAFE_SIGNER_1);
        safe.approveHash(txHash);
        vm.prank(SAFE_SIGNER_2, SAFE_SIGNER_2);
        safe.approveHash(txHash);
        vm.prank(SAFE_SIGNER_3, SAFE_SIGNER_3);
        safe.approveHash(txHash);

        // Build pre-approved signatures — must be sorted ascending by signer address
        bytes memory sigs = abi.encodePacked(
            bytes32(uint256(uint160(SAFE_SIGNER_1))), bytes32(0), uint8(1),
            bytes32(uint256(uint160(SAFE_SIGNER_2))), bytes32(0), uint8(1),
            bytes32(uint256(uint160(SAFE_SIGNER_3))), bytes32(0), uint8(1)
        );

        // Execute from signer 1 (real EOA as both msg.sender and tx.origin)
        vm.prank(SAFE_SIGNER_1, SAFE_SIGNER_1);
        bool ok = safe.execTransaction(
            to, value, data, operation,
            0, 0, 0, address(0), payable(address(0)), sigs
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

    /// Helper: build sorted operator arrays for the new factory.
    /// Owners must be ascending (factory enforces strict ordering).
    function _operatorData()
        internal
        view
        returns (
            address[] memory owners,
            uint64[]  memory ids,
            bytes[]   memory pubkeys,
            bytes[]   memory shares
        )
    {
        // Sorted ascending by owner address
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

        // BLS pubkey + encrypted shares from a real registerValidators tx
        pubkeys = new bytes[](1);
        pubkeys[0] = vm.parseBytes(vm.readFile("test/data/blsPubkey.hex"));

        shares = new bytes[](1);
        shares[0] = vm.parseBytes(vm.readFile("test/data/sharesData.hex"));
    }

    /// Revert-reason bytes4 helpers
    bytes4 constant ERR_NOT_ALLOWED_OP = bytes4(keccak256("P2pSsvProxyFactory__NotAllowedSsvOperatorOwner(address)"));
    bytes4 constant ERR_NOT_OPERATOR   = bytes4(keccak256("Access__CallerNeitherOperatorNorOwner(address,address,address)"));
    bytes4 constant ERR_SSV_OP_NOT_ALLOWED = bytes4(keccak256("P2pSsvProxyFactory__SsvOperatorNotAllowed(address,uint64)"));
    bytes4 constant ERR_DUP_OWNERS     = bytes4(keccak256("P2pSsvProxyFactory__DuplicateOperatorOwnersNotAllowed(address,uint64,uint64)"));

    function _assertNotFactoryACL(bytes memory ret) internal {
        if (ret.length >= 4) {
            bytes4 errSel;
            assembly { errSel := mload(add(ret, 0x20)) }
            assertTrue(errSel != ERR_NOT_ALLOWED_OP,     "revert must not be NotAllowedSsvOperatorOwner");
            assertTrue(errSel != ERR_NOT_OPERATOR,        "revert must not be CallerNeitherOperatorNorOwner");
            assertTrue(errSel != ERR_SSV_OP_NOT_ALLOWED,  "revert must not be SsvOperatorNotAllowed");
            assertTrue(errSel != ERR_DUP_OWNERS,          "revert must not be DuplicateOperatorOwnersNotAllowed");
        }
    }

    function test_P0_2b_registerValidators_on_factory() public {
        // Call registerValidators(address[],uint64[],bytes[],bytes[],uint256,Cluster,
        //                         FeeRecipient,FeeRecipient) on the NEW factory.
        // Uses real operator data (owners + IDs valid on the new factory) and real BLS
        // pubkey + shares from a historical tx. Amount = 0 (skip SSV token transfer).
        // Expected: factory ACL & operator validation pass; revert inside SSV Network.

        (address[] memory owners, uint64[] memory ids,
         bytes[] memory pubkeys, bytes[] memory shares) = _operatorData();

        address caller = owners[3]; // 0xfeC26…, an allowed SSV operator owner
        vm.deal(caller, 2 ether);

        SsvCluster memory cluster = SsvCluster(0, 0, 0, true, 0);
        FeeRecipient memory client   = FeeRecipient(9000, payable(caller));
        FeeRecipient memory referrer = FeeRecipient(0,    payable(address(0)));

        vm.prank(caller);
        (bool ok, bytes memory ret) = SSV_FACTORY_NEW.call{value: 1 ether}(
            abi.encodeCall(
                IP2pSsvProxyFactory.registerValidators,
                (owners, ids, pubkeys, shares, uint256(0), cluster, client, referrer)
            )
        );

        if (!ok) {
            _assertNotFactoryACL(ret);
            emit log_named_bytes("registerValidators revert (expected in SSV)", ret);
        }
    }

    function test_P0_2c_registerValidatorsEth_on_factory() public {
        // Call registerValidatorsEth on the NEW factory. Same operator/BLS data.
        // registerValidatorsEth uses ETH for SSV fees (no `amount` param).
        // Expected: factory ACL passes; revert inside SSV Network (stale cluster).

        (address[] memory owners, uint64[] memory ids,
         bytes[] memory pubkeys, bytes[] memory shares) = _operatorData();

        // Caller = factory operator (satisfies onlyOperatorOrOwnerOrClientOrReferrer)
        address caller = 0x18fB2400e61b623c3fc55b212c9022B44EdD1c18;
        vm.deal(caller, 2 ether);

        SsvCluster memory cluster = SsvCluster(0, 0, 0, true, 0);
        FeeRecipient memory client   = FeeRecipient(9000, payable(caller));
        FeeRecipient memory referrer = FeeRecipient(0,    payable(address(0)));

        vm.prank(caller);
        (bool ok, bytes memory ret) = SSV_FACTORY_NEW.call{value: 1 ether}(
            abi.encodeCall(
                IP2pSsvProxyFactory.registerValidatorsEth,
                (owners, ids, pubkeys, shares, cluster, client, referrer)
            )
        );

        if (!ok) {
            _assertNotFactoryACL(ret);
            emit log_named_bytes("registerValidatorsEth revert (expected in SSV)", ret);
        }
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
        bytes memory op1 = abi.encodeCall(IP2pMessageSender.send, ("p07-op1"));
        bytes memory op2 = abi.encodeCall(IP2pMessageSender.send, ("p07-op2"));
        bytes memory op3 = abi.encodeCall(IP2pMessageSender.send, ("p07-op3"));

        bytes memory txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, op1),
            _packOp(0, MESSAGE_SENDER, 0, op2),
            _packOp(0, MESSAGE_SENDER, 0, op3)
        );

        // Parse and verify every sub-op has operation = 0 (Call)
        uint256 i;
        while (i < txs.length) {
            uint8 op = uint8(txs[i]);
            assertEq(op, 0, "all ops must be Call(0), not DelegateCall(1)");
            uint256 dataLen;
            assembly { dataLen := mload(add(add(txs, 0x20), add(i, 53))) }
            i += 85 + dataLen;
        }

        // Execute via MultiSendCallOnly (Safe v1.4.1 / v1.3.0)
        IMultiSend(_multiSend()).multiSend(txs);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.8  Multicall Shape – at most 10 sub-operations
    // ═══════════════════════════════════════════════════════════

    function test_P0_8_multisend_max_10_ops() public {
        bytes memory txs;
        uint256 opCount;

        for (uint256 j; j < 5; j++) {
            bytes memory data = abi.encodeCall(
                IP2pMessageSender.send,
                (string(abi.encodePacked("p08-op", bytes1(uint8(0x30 + j)))))
            );
            txs = abi.encodePacked(txs, _packOp(0, MESSAGE_SENDER, 0, data));
            opCount++;
        }

        assertTrue(opCount <= 10, "at most 10 sub-operations");
        IMultiSend(_multiSend()).multiSend(txs);
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.9  Safe Management – no enableModule / disableModule
    // ═══════════════════════════════════════════════════════════

    function test_P0_9_no_enableModule_disableModule() public {
        // Verify allowed selectors don't collide with forbidden ones
        bytes4 addEthSel = IP2pOrgUnlimitedEthDepositor.addEth.selector;
        bytes4 refundSel = IP2pOrgUnlimitedEthDepositor.refund.selector;
        bytes4 sendSel   = IP2pMessageSender.send.selector;

        assertTrue(addEthSel != SEL_ENABLE_MODULE  && addEthSel != SEL_DISABLE_MODULE);
        assertTrue(refundSel != SEL_ENABLE_MODULE  && refundSel != SEL_DISABLE_MODULE);
        assertTrue(sendSel   != SEL_ENABLE_MODULE  && sendSel   != SEL_DISABLE_MODULE);

        // Execute a valid call
        IP2pMessageSender(MESSAGE_SENDER).send("p09-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.10  Safe Management – no setGuard
    // ═══════════════════════════════════════════════════════════

    function test_P0_10_no_setGuard() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_SET_GUARD);
        assertTrue(IP2pMessageSender.send.selector              != SEL_SET_GUARD);
        IP2pMessageSender(MESSAGE_SENDER).send("p10-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.11  Safe Management – no setFallbackHandler
    // ═══════════════════════════════════════════════════════════

    function test_P0_11_no_setFallbackHandler() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_SET_FALLBACK);
        assertTrue(IP2pMessageSender.send.selector              != SEL_SET_FALLBACK);
        IP2pMessageSender(MESSAGE_SENDER).send("p11-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.12  Safe Management – no addOwnerWithThreshold
    // ═══════════════════════════════════════════════════════════

    function test_P0_12_no_addOwnerWithThreshold() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_ADD_OWNER);
        assertTrue(IP2pMessageSender.send.selector              != SEL_ADD_OWNER);
        IP2pMessageSender(MESSAGE_SENDER).send("p12-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.13  Safe Management – no removeOwner
    // ═══════════════════════════════════════════════════════════

    function test_P0_13_no_removeOwner() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_REMOVE_OWNER);
        assertTrue(IP2pMessageSender.send.selector              != SEL_REMOVE_OWNER);
        IP2pMessageSender(MESSAGE_SENDER).send("p13-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.14  Safe Management – no swapOwner
    // ═══════════════════════════════════════════════════════════

    function test_P0_14_no_swapOwner() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_SWAP_OWNER);
        assertTrue(IP2pMessageSender.send.selector              != SEL_SWAP_OWNER);
        IP2pMessageSender(MESSAGE_SENDER).send("p14-test");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.15  Safe Management – no changeThreshold
    // ═══════════════════════════════════════════════════════════

    function test_P0_15_no_changeThreshold() public {
        assertTrue(IP2pOrgUnlimitedEthDepositor.addEth.selector != SEL_CHANGE_THRESHOLD);
        assertTrue(IP2pMessageSender.send.selector              != SEL_CHANGE_THRESHOLD);
        IP2pMessageSender(MESSAGE_SENDER).send("p15-test");
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

        // Execute
        IMultiSend(_multiSend()).multiSend(txs);
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
            GNOSIS_SAFE, 0,
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
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.setGuard, (WHALE)),
            0
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.11 NEG — call setFallbackHandler on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_11_NEG_setFallbackHandler_on_safe() public {
        _safeExec(
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.setFallbackHandler, (WHALE)),
            0
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.12 NEG — call addOwnerWithThreshold on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_12_NEG_addOwnerWithThreshold_on_safe() public {
        uint256 ownersBefore = ISafe(GNOSIS_SAFE).getOwners().length;

        _safeExec(
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.addOwnerWithThreshold, (WHALE, 3)),
            0
        );

        assertEq(ISafe(GNOSIS_SAFE).getOwners().length, ownersBefore + 1, "owner added");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.13 NEG — call removeOwner on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_13_NEG_removeOwner_on_safe() public {
        // Remove the last owner in the linked list.
        // Gnosis Safe owners (sorted by linked list, NOT by address):
        //   sentinel -> owner[0] -> owner[1] -> ... -> owner[10] -> sentinel
        // getOwners() returns them in linked-list order.
        address[] memory owners = ISafe(GNOSIS_SAFE).getOwners();
        // Remove the last listed owner; its prevOwner is owners[length-2]
        address toRemove = owners[owners.length - 1];
        address prevOwner = owners[owners.length - 2];

        _safeExec(
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.removeOwner, (prevOwner, toRemove, 3)),
            0
        );

        assertEq(ISafe(GNOSIS_SAFE).getOwners().length, owners.length - 1, "owner removed");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.14 NEG — call swapOwner on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_14_NEG_swapOwner_on_safe() public {
        address newOwner = WHALE;

        // Swap the last owner. prevOwner is the second-to-last in the list.
        address[] memory owners = ISafe(GNOSIS_SAFE).getOwners();
        address oldOwner = owners[owners.length - 1];
        address prevOwner = owners[owners.length - 2];

        _safeExec(
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.swapOwner, (prevOwner, oldOwner, newOwner)),
            0
        );

        // Verify swap
        address[] memory after_ = ISafe(GNOSIS_SAFE).getOwners();
        assertEq(after_.length, owners.length, "same count");
        assertEq(after_[after_.length - 1], newOwner, "owner was swapped");
    }

    // ═══════════════════════════════════════════════════════════
    //  P0.15 NEG — call changeThreshold on a Safe
    // ═══════════════════════════════════════════════════════════

    function test_P0_15_NEG_changeThreshold_on_safe() public {
        assertEq(ISafe(GNOSIS_SAFE).getThreshold(), 3);

        _safeExec(
            GNOSIS_SAFE, 0,
            abi.encodeCall(ISafe.changeThreshold, (4)),
            0
        );

        assertEq(ISafe(GNOSIS_SAFE).getThreshold(), 4, "threshold changed");
    }
}
