// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

struct FeeRecipient {
    uint96 basisPoints;
    address payable recipient;
}

interface IP2pOrgUnlimitedEthDepositor {
    function addEth(bytes32, uint96, address, FeeRecipient calldata, FeeRecipient calldata, bytes calldata) external payable returns (bytes32, address);
    function refund(bytes32, uint96, address) external;
    function totalBalance() external view returns (uint256);
    function supportsInterface(bytes4) external view returns (bool);
    function depositExpiration(bytes32) external view returns (uint40);
    function getDepositId(bytes32, uint96, address, FeeRecipient calldata, FeeRecipient calldata) external view returns (bytes32);
}

interface IFeeDistributorFactory {
    function predictFeeDistributorAddress(address, FeeRecipient calldata, FeeRecipient calldata) external view returns (address);
}

interface IP2pSsvProxyFactory {
    function addEth(bytes32, uint96, FeeRecipient calldata, FeeRecipient calldata, bytes calldata) external payable returns (bytes32, address, address);
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
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Generates calldata for all 30 tx rows and writes the markdown table.
contract GenerateTxTable is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 24788000);
    }

    address constant DEPOSITOR       = 0x23BE839a14cEc3D6D716D904f09368Bbf9c750eb;
    address constant SSV_FACTORY_NEW = 0x7F12A9904bA021AE3ecE106e10f476b7AfBd830C;
    address constant SSV_FACTORY_OLD = 0x5ed861aec31cCB496689FD2E0A1a3F8e8D7B8824;
    address constant MESSAGE_SENDER  = 0x4E1224f513048e18e7a1883985B45dc0Fe1D917e;
    address constant ETH2_DEP_LEGACY = 0x4CA21E4D3A86e7399698F88686f5596dBe74ADEb;
    address constant ETH2_DEP_V2     = 0x8e76a33f1aFf7EB15DE832810506814aF4789536;
    address constant REF_FEE_DIST    = 0x3Fcd8D9aCAc042095dFbA53f4C40C74d19E2e9D9;
    address constant MULTISEND_FULL  = 0x38869BF66A61CF6BDDB996A6AE40d5853fd43b52;
    address constant SAFE_ADDR       = 0x4F2083f5fBede34C2714aFfb3105539775f7FE64;
    address constant WHALE           = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;
    address constant WHALE_2         = 0x40B38765696e3d5d8d9d834D8AaD4bB6e418E489;
    address constant USDC            = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DEPOSITOR_OPERATOR = 0x632788138aa5eac1548b65B41a3d913c291E4cEF;
    address constant LEGACY_DEP_OWNER   = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant DEPOSITOR_FEE_FACTORY = 0xecA6e48C44C7c0cAf4651E5c5089e564031E8b90;

    function _creds(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a))) | bytes32(bytes1(0x01));
    }

    function _packOp(uint8 op, address to, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(op, to, value, uint256(data.length), data);
    }

    function _row(string memory id, string memory from_, address to, uint256 value, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            "| ", id, " | from: `", from_,
            "`<br>to: `", vm.toString(to),
            "`<br>value: `", vm.toString(value),
            "`<br>data: `", vm.toString(data),
            "` | `", vm.toString(abi.encodePacked(to, value, data)), "` |\n"
        );
    }

    function test_generateTable() public {
        string memory md = "# Transaction Data for Tenderly Simulation\n\n";
        md = string.concat(md, "Fork block: **24788000**\n\n");
        md = string.concat(md, "| # | Transaction fields | Raw (to \\|\\| value \\|\\| data) |\n");
        md = string.concat(md, "|---|---|---|\n");

        // ── P0.1 POS: addEth on Depositor ────────────────────
        bytes memory p01pos = abi.encodeCall(IP2pOrgUnlimitedEthDepositor.addEth, (
            _creds(WHALE), uint96(32 ether), REF_FEE_DIST,
            FeeRecipient(9000, payable(WHALE)),
            FeeRecipient(0, payable(address(0))), ""
        ));
        md = string.concat(md, _row("P0.1 POS", vm.toString(WHALE), DEPOSITOR, 32 ether, p01pos));

        // ── P0.1 NEG: rejectService on Depositor ─────────────
        // Need a real depositId. Use addEth first to get one.
        vm.deal(WHALE, 33 ether);
        vm.prank(WHALE);
        (bytes32 depId,) = IP2pOrgUnlimitedEthDepositor(DEPOSITOR).addEth{value: 32 ether}(
            _creds(WHALE), uint96(32 ether), REF_FEE_DIST,
            FeeRecipient(9000, payable(WHALE)), FeeRecipient(0, payable(address(0))), ""
        );
        bytes memory p01neg = abi.encodeWithSignature("rejectService(bytes32,string)", depId, "test rejection");
        md = string.concat(md, _row("P0.1 NEG", vm.toString(DEPOSITOR_OPERATOR), DEPOSITOR, 0, p01neg));

        // ── P0.2 POS: addEth on SsvProxyFactory ──────────────
        // Uses raw calldata from real tx (loaded from file)
        bytes memory p02pos = vm.parseBytes(vm.readFile("test/data/factoryAddEth.hex"));
        md = string.concat(md, _row("P0.2 POS", "0x6717F57a7E18c4758f0E83E786E08cE538e0436C", SSV_FACTORY_OLD, 71 ether, p02pos));

        // ── P0.2 NEG: changeOperator on Factory ──────────────
        bytes memory p02neg = abi.encodeWithSignature("changeOperator(address)", WHALE_2);
        md = string.concat(md, _row("P0.2 NEG", "0x18fB2400e61b623c3fc55b212c9022B44EdD1c18", SSV_FACTORY_NEW, 0, p02neg));

        // ── P0.3 POS: send on MessageSender ──────────────────
        bytes memory p03pos = abi.encodeCall(IP2pMessageSender.send, ('{"action":"withdraw","pubkeys":["0xabc123"]}'));
        md = string.concat(md, _row("P0.3 POS", vm.toString(WHALE), MESSAGE_SENDER, 0, p03pos));

        // ── P0.3 NEG: no other callable function exists ──────
        // Show a transfer(address,uint256) selector aimed at MessageSender
        bytes memory p03neg = abi.encodeWithSignature("transfer(address,uint256)", WHALE, uint256(0));
        md = string.concat(md, _row("P0.3 NEG", vm.toString(WHALE), MESSAGE_SENDER, 0, p03neg));

        // ── P0.4 POS: deposit on legacy P2pEth2Depositor ─────
        bytes memory p04pos = vm.parseBytes(vm.readFile("test/data/depositLegacy.hex"));
        md = string.concat(md, _row("P0.4 POS", "0x1461Da3E1b86EA1Aa273eC32664758e5E192233a", ETH2_DEP_LEGACY, 32 ether, p04pos));

        // ── P0.4 NEG: pause on legacy depositor ──────────────
        bytes memory p04neg = abi.encodeWithSignature("pause()");
        md = string.concat(md, _row("P0.4 NEG", vm.toString(LEGACY_DEP_OWNER), ETH2_DEP_LEGACY, 0, p04neg));

        // ── P0.5 POS: call to P2P contract (not token) ───────
        bytes memory p05pos = abi.encodeCall(IP2pOrgUnlimitedEthDepositor.supportsInterface, (bytes4(0x01ffc9a7)));
        md = string.concat(md, _row("P0.5 POS", vm.toString(WHALE), DEPOSITOR, 0, p05pos));

        // ── P0.5 NEG: USDC transfer (targets token contract) ─
        bytes memory p05neg = abi.encodeCall(IERC20.transfer, (WHALE_2, 100e6));
        md = string.concat(md, _row("P0.5 NEG", vm.toString(WHALE), USDC, 0, p05neg));

        // ── P0.6 POS: ETH to known P2P contract ──────────────
        md = string.concat(md, _row("P0.6 POS", vm.toString(WHALE), DEPOSITOR, 32 ether, p01pos));

        // ── P0.6 NEG: ETH to unknown address ─────────────────
        md = string.concat(md, _row("P0.6 NEG", vm.toString(WHALE), WHALE_2, 1 ether, hex""));

        // ── P0.7 POS: multiSend with all operation=0 ─────────
        bytes memory p07txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, abi.encodeCall(IP2pMessageSender.send, ('{"action":"status"}'))),
            _packOp(0, DEPOSITOR, 0, abi.encodeWithSelector(IP2pOrgUnlimitedEthDepositor.totalBalance.selector)),
            _packOp(0, SSV_FACTORY_NEW, 0, abi.encodeWithSelector(bytes4(0x7c8c9f2e)))
        );
        bytes memory p07pos = abi.encodeCall(IMultiSend.multiSend, (p07txs));
        md = string.concat(md, _row("P0.7 POS", vm.toString(SAFE_ADDR), MULTISEND_FULL, 0, p07pos));

        // ── P0.7 NEG: multiSend with operation=1 (delegatecall)
        bytes memory sendData = abi.encodeCall(IP2pMessageSender.send, ("delegatecall-test"));
        bytes memory p07negtxs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, sendData),
            _packOp(1, MESSAGE_SENDER, 0, sendData)
        );
        bytes memory p07neg = abi.encodeCall(IMultiSend.multiSend, (p07negtxs));
        md = string.concat(md, _row("P0.7 NEG", vm.toString(SAFE_ADDR), MULTISEND_FULL, 0, p07neg));

        // ── P0.8 POS: multiSend with 5 ops (≤10) ─────────────
        bytes memory p08txs = abi.encodePacked(
            _packOp(0, MESSAGE_SENDER, 0, abi.encodeCall(IP2pMessageSender.send, ('{"action":"ping"}'))),
            _packOp(0, DEPOSITOR, 0, abi.encodeWithSelector(IP2pOrgUnlimitedEthDepositor.totalBalance.selector)),
            _packOp(0, DEPOSITOR, 0, abi.encodeCall(IP2pOrgUnlimitedEthDepositor.supportsInterface, (bytes4(0x01ffc9a7)))),
            _packOp(0, SSV_FACTORY_NEW, 0, abi.encodeWithSelector(bytes4(0x7c8c9f2e))),
            _packOp(0, SSV_FACTORY_NEW, 0, abi.encodeCall(IP2pSsvProxyFactory.supportsInterface, (bytes4(0x01ffc9a7))))
        );
        bytes memory p08pos = abi.encodeCall(IMultiSend.multiSend, (p08txs));
        md = string.concat(md, _row("P0.8 POS", vm.toString(SAFE_ADDR), MULTISEND_FULL, 0, p08pos));

        // ── P0.8 NEG: multiSend with 11 ops (>10) ────────────
        bytes memory p08negtxs;
        for (uint256 j; j < 11; j++) {
            p08negtxs = abi.encodePacked(p08negtxs, _packOp(0, MESSAGE_SENDER, 0,
                abi.encodeCall(IP2pMessageSender.send, (string(abi.encodePacked("neg-op", bytes1(uint8(0x30 + j))))))));
        }
        bytes memory p08neg = abi.encodeCall(IMultiSend.multiSend, (p08negtxs));
        md = string.concat(md, _row("P0.8 NEG", vm.toString(SAFE_ADDR), MULTISEND_FULL, 0, p08neg));

        // ── P0.9 POS: Safe → addEth on Depositor ─────────────
        md = string.concat(md, _row("P0.9 POS", vm.toString(SAFE_ADDR), DEPOSITOR, 32 ether, p01pos));

        // ── P0.9 NEG: enableModule on Safe ────────────────────
        bytes memory p09neg = abi.encodeCall(ISafe.enableModule, (WHALE));
        md = string.concat(md, _row("P0.9 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p09neg));

        // ── P0.10 POS: Safe → refund on Depositor ────────────
        // refund needs the fee distributor address from a prior addEth
        address feeDist = IFeeDistributorFactory(DEPOSITOR_FEE_FACTORY).predictFeeDistributorAddress(
            REF_FEE_DIST, FeeRecipient(9000, payable(SAFE_ADDR)), FeeRecipient(0, payable(address(0))));
        bytes memory p10pos = abi.encodeCall(IP2pOrgUnlimitedEthDepositor.refund, (
            _creds(SAFE_ADDR), uint96(32 ether), feeDist));
        md = string.concat(md, _row("P0.10 POS", vm.toString(SAFE_ADDR), DEPOSITOR, 0, p10pos));

        // ── P0.10 NEG: setGuard on Safe ──────────────────────
        bytes memory p10neg = abi.encodeCall(ISafe.setGuard, (WHALE));
        md = string.concat(md, _row("P0.10 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p10neg));

        // ── P0.11 POS: Safe → send on MessageSender ──────────
        bytes memory p11pos = abi.encodeCall(IP2pMessageSender.send, ('{"action":"withdraw","pubkeys":["0xabc123"]}'));
        md = string.concat(md, _row("P0.11 POS", vm.toString(SAFE_ADDR), MESSAGE_SENDER, 0, p11pos));

        // ── P0.11 NEG: setFallbackHandler on Safe ────────────
        bytes memory p11neg = abi.encodeCall(ISafe.setFallbackHandler, (WHALE));
        md = string.concat(md, _row("P0.11 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p11neg));

        // ── P0.12 POS: Safe → totalBalance on Depositor ──────
        bytes memory p12pos = abi.encodeWithSelector(IP2pOrgUnlimitedEthDepositor.totalBalance.selector);
        md = string.concat(md, _row("P0.12 POS", vm.toString(SAFE_ADDR), DEPOSITOR, 0, p12pos));

        // ── P0.12 NEG: addOwnerWithThreshold on Safe ─────────
        bytes memory p12neg = abi.encodeCall(ISafe.addOwnerWithThreshold, (WHALE, 1));
        md = string.concat(md, _row("P0.12 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p12neg));

        // ── P0.13 POS: Safe → supportsInterface on Depositor ─
        bytes memory p13pos = abi.encodeCall(IP2pOrgUnlimitedEthDepositor.supportsInterface, (bytes4(0x01ffc9a7)));
        md = string.concat(md, _row("P0.13 POS", vm.toString(SAFE_ADDR), DEPOSITOR, 0, p13pos));

        // ── P0.13 NEG: removeOwner on Safe ───────────────────
        // After addOwner(WHALE), list is sentinel→WHALE→SIGNER→sentinel
        bytes memory p13neg = abi.encodeCall(ISafe.removeOwner, (address(0x1), WHALE, 1));
        md = string.concat(md, _row("P0.13 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p13neg));

        // ── P0.14 POS: Safe → getReferenceFeeDistributor ─────
        bytes memory p14pos = abi.encodeWithSelector(bytes4(0x7c8c9f2e));
        md = string.concat(md, _row("P0.14 POS", vm.toString(SAFE_ADDR), SSV_FACTORY_NEW, 0, p14pos));

        // ── P0.14 NEG: swapOwner on Safe ─────────────────────
        bytes memory p14neg = abi.encodeCall(ISafe.swapOwner, (address(0x1), SAFE_ADDR, WHALE));
        md = string.concat(md, _row("P0.14 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p14neg));

        // ── P0.15 POS: Safe → supportsInterface on Factory ───
        bytes memory p15pos = abi.encodeCall(IP2pSsvProxyFactory.supportsInterface, (bytes4(0x01ffc9a7)));
        md = string.concat(md, _row("P0.15 POS", vm.toString(SAFE_ADDR), SSV_FACTORY_NEW, 0, p15pos));

        // ── P0.15 NEG: changeThreshold on Safe ───────────────
        bytes memory p15neg = abi.encodeCall(ISafe.changeThreshold, (2));
        md = string.concat(md, _row("P0.15 NEG", vm.toString(SAFE_ADDR), SAFE_ADDR, 0, p15neg));

        vm.writeFile("Tx-Data-Table.md", md);
    }
}
