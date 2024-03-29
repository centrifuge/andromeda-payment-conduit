// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Conduit} from "../../src/Conduit.sol";
import {ERC20} from "../../src/token/ERC20.sol";

interface RootLike {
    function poolManager() external returns (address);
    function gateway() external returns (address);
}

interface PoolManagerLike {
    function currencyIdToAddress(uint128 currencyId) external returns (address);
    function addCurrency(uint128 currencyId, address currency) external;
    function allowInvestmentCurrency(uint64 poolId, uint128 currencyId) external;
    function isAllowedAsInvestmentCurrency(uint64 poolId, address currency) external returns (bool);
    function deployLiquidityPool(uint64 poolId, bytes16 trancheId, address currency) external returns (address);
    function updateMember(uint64 poolId, bytes16 trancheId, address user, uint64 validUntil) external;
    function handleTransfer(uint128 currency, address recipient, uint128 amount) external;
}

interface InvestmentManagerLike {
    function handleExecutedCollectInvest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout,
        uint128 remainingInvestOrder
    ) external;
    function handleExecutedCollectRedeem(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 currencyId,
        uint128 currencyPayout,
        uint128 trancheTokenPayout,
        uint128 remainingInvestOrder
    ) external;
}

interface AuthLike {
    function rely(address user) external;
    function hope(address user) external;
    function mate(address user) external;
    function kiss(address user) external;
    function can(address user) external returns (uint256);
    function may(address user) external returns (uint256);
    function bud(address user) external returns (uint256);
}

interface ERC20Like {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external returns (uint256 amount);
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;
    function totalSupply() external returns (uint256);
}

interface UrnLike {
    function draw(uint256 amount) external;
    function wipe(uint256 amount) external;
    function gemJoin() external view returns (address);
}

interface JarLike {
    function void() external;
}

interface JugLike {
    function ilks(bytes32) external view returns (uint256, uint256);
    function drip(bytes32 ilk) external returns (uint256 rate);
    function base() external view returns (uint256);
}

interface VatLike {
    function urns(bytes32, address) external view returns (uint256, uint256);
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

interface GemJoinLike {
    function ilk() external view returns (bytes32);
}

contract ForkTest is Test {
    Conduit public conduit;

    // MAKER
    address constant VAT = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address constant JUG = 0x19c0976f590D67707E62397C87829d896Dc0f1F1;
    address constant URN = 0xebFDaa143827FD0fc9C6637c3604B75Bbcfb7284;
    address constant JAR = 0xc27C3D3130563C1171feCC4F76C217Db603997cf;
    address constant OUTPUT_CONDUIT = 0x1E86CB085f249772f7e7443631a87c6BDba2aCEb;
    address constant URN_CONDUIT = 0xe08cb5E24862eA86328295D5E5c08972203C20D8;
    address constant JAR_CONDUIT = 0xB9373C557f3aE8cDdD068c1644ED226CfB18A997;
    address constant WARD = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB; // ward on Maker contracts
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // GEM
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // NOT WORKING WITH THAT PSM -> address constant PSM = 0x204659B2Fd2aD5723975c362Ce2230Fba11d3900;
    address constant PSM = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;

    // PERMISSIONS
    address constant OPERATOR = 0x23a10f09Fac6CCDbfb6d9f0215C795F9591D7476; // OPERATOR = ANKURA
    address constant MATE = 0x23a10f09Fac6CCDbfb6d9f0215C795F9591D7476; // MATE = ANKURA
    address constant WITHDRAW_ADDRESS = 0x65729807485F6f7695AF863d97D62140B7d69d83; // WITHDRAW ADDRESS

    // CENTRIFUGE POOL
    address root = 0x498016d30Cd5f0db50d7ACE329C07313a0420502;
    address gateway = 0x634F036fE66579E901c7bA34e33DF422E37A0037;
    address escrow = 0xd595E1483c507E74E2E6A3dE8e7D08d8f6F74936;
    PoolManagerLike poolManager = PoolManagerLike(0x78E9e622A57f70F1E0Ec652A4931E4e278e58142);
    InvestmentManagerLike investmentManager = InvestmentManagerLike(0xbBF0AB988691dB1892ADaF7F0eF560Ca4c6DD73A);
    uint64 poolId = 4139607887; // Anemoy pool
    bytes16 trancheId = 0x97aa65f23e7be09fcd62d0554d2e9273; // Anemoy tranche
    address trancheToken = 0x30baA3BA9D7089fD8D020a994Db75D14CF7eC83b; // Anemoy tranche token
    uint128 currencyId = 999; // pick random id to add currency
    address asset;
    address pool;

    address self;
    uint256 constant ONE = 1000000000000000000000000000;

    function setUp() public virtual {
        self = address(this);

        string memory rpcUrl = "https://mainnet.infura.io/v3/28b9df37a970456197cdb6b73af4e6de";
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);

        deployContracts();
    }

    function deployContracts() internal {
        // deploy depositAsset
        asset = address(new ERC20("LPUSDC", "LPUSDC", 6));
        // add depositAsset to pool currencies (use existing Anemoy pool for testing)
        addCurrency(asset);
        // deploy pool for depositAsset
        pool = poolManager.deployLiquidityPool(poolId, trancheId, asset);
        // deploy and wire conduit
        conduit = new Conduit(PSM, DAI, USDC, asset, OUTPUT_CONDUIT, URN_CONDUIT, JAR_CONDUIT);
        // allow conduit to receive LP tokens
        addTrancheTokenMember(address(conduit));
        // allow conduit to mint deposit assets
        AuthLike(asset).rely(address(conduit));

        // set Maker permissions on conduit
        conduit.mate(MATE);
        assertEq(conduit.may(MATE), 1);
        conduit.hope(OPERATOR);
        assertEq(conduit.can(OPERATOR), 1);
        // wire conduit with Maker contracts
        vm.startPrank(WARD); // make self as ward on Maker contracts to wire conduit
        AuthLike(OUTPUT_CONDUIT).mate(address(conduit));
        assertEq(AuthLike(OUTPUT_CONDUIT).may(address(conduit)), 1);
        AuthLike(OUTPUT_CONDUIT).hope(address(conduit));
        assertEq(AuthLike(OUTPUT_CONDUIT).can(address(conduit)), 1);
        AuthLike(OUTPUT_CONDUIT).kiss(address(conduit));
        assertEq(AuthLike(OUTPUT_CONDUIT).bud(address(conduit)), 1);
        vm.stopPrank();
        // wire conduit with LP contracts
        vm.prank(OPERATOR);
        conduit.file("pool", pool, address(poolManager));
        // set ANDROMEDA addresses
        conduit.file("withdrawal", address(this)); // use deployer as withdrawel address for testing
        vm.prank(OPERATOR);
        conduit.file("depositRecipient", "DepositRecipient"); // use random String for testing
    }

    function testDeposit(uint128 amount) public {
        // bound(amount, 2000000000000000000, 50000000000000000000000000);
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
    }

    function testWithdrawFromPool(uint128 amount) public {
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
    }

    function testEmergencyWithdrawFromPool(uint128 amount) public {
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        uint256 withdrawalWalletBalanceBeforeWithdrawRequestUSDC =
            ERC20Like(USDC).balanceOf(address(conduit.withdrawal()));
        // do not transfer depositAssets from Centrifuge chain => conduit does not have depositAssets to butn for
        // withdrawal

        vm.startPrank(MATE);
        vm.expectRevert("AndromedaPaymentConduit/nothing-to-withdraw"); // withdrawal should fail
        conduit.withdrawFromPool();
        // mint depositAssets to conduit for emergency withdrawal
        conduit.authMint(amount / 10 ** 12);
        conduit.withdrawFromPool();
        vm.stopPrank();

        assertEq(
            ERC20Like(USDC).balanceOf(conduit.withdrawal()),
            withdrawalWalletBalanceBeforeWithdrawRequestUSDC + amount / 10 ** 12 // normalize decimals
        );
    }

    function testDepositIntoPool(uint128 amount) public {
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
    }

    function testRedeem(uint128 amount) public {
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
        redeem(amount);
    }

    function testRepayMaker(uint128 amount) public {
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
        redeem(amount);
        repayMaker(amount);
    }

    function testEmergencyRepayMaker(uint128 amount) public {
        amount = 50000000000000000000000000;
        uint256 repaymentAmount = (amount / 10 ** 12) / 2;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
        // do not redeem => gem locked
        vm.startPrank(MATE);
        vm.expectRevert("AndromedaPaymentConduit/no-unlocked-gem-left");
        conduit.repayToUrn(repaymentAmount);
        vm.expectRevert("AndromedaPaymentConduit/no-unlocked-gem-left");
        conduit.repayToJar(repaymentAmount);
        conduit.unlock(); // unlock gem for emergency Maker repayment
        vm.stopPrank();
        repayMaker(amount);
    }

    function drawGemFromVault(uint128 amount) internal {
        uint256 outputConduitBalanceBeforeDrawDAI = ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT));
        vm.prank(MATE); // call as Ankura
        UrnLike(URN).draw(amount); // draw DAI from vault in case output_conduit has no DAI
        assertEq(ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT)), amount + outputConduitBalanceBeforeDrawDAI);
    }

    function repayMaker(uint128 amount) internal {
        uint256 debtBeforeRepayment = makerDebt();
        uint256 conduitBalanceBeforeRepaymentUSDC = ERC20Like(USDC).balanceOf(address(conduit));

        // is not triggered
        uint256 jarBalanceBeforeRepaymentDAI = ERC20Like(DAI).balanceOf(JAR);
        uint256 urnBalanceBeforeRepaymentDAI = ERC20Like(DAI).balanceOf(URN);
        uint256 repaymentAmount = (amount / 10 ** 12) / 2;

        vm.startPrank(MATE);
        conduit.repayToUrn(repaymentAmount); // repay debt
        conduit.repayToJar(repaymentAmount); // repay interest
        vm.stopPrank();

        assertEq(ERC20Like(USDC).balanceOf(address(conduit)), conduitBalanceBeforeRepaymentUSDC - 2 * repaymentAmount);
        assertEq(ERC20Like(DAI).balanceOf(URN), urnBalanceBeforeRepaymentDAI + repaymentAmount * 10 ** 12);
        // move DAI Maker Vault - wipe debt
        UrnLike(URN).wipe(repaymentAmount * 10 ** 12);
        assertEq(ERC20Like(DAI).balanceOf(URN), urnBalanceBeforeRepaymentDAI);
        assertEq(makerDebt(), debtBeforeRepayment - repaymentAmount * 10 ** 39); // 12 + 27 (normalize to 12 decimals
            // DAI and 27 for precision)

        assertEq(ERC20Like(DAI).balanceOf(JAR), jarBalanceBeforeRepaymentDAI + repaymentAmount * 10 ** 12);
        // move DAI to suprlus buffer
        JarLike(JAR).void();
        assertEq(ERC20Like(DAI).balanceOf(JAR), 0);
    }

    function withdrawFromPool(uint128 amount) internal {
        uint256 escrowBalanceBeforeWithdrawRequestASSET = ERC20Like(asset).balanceOf(escrow);
        uint256 unlockedGem = conduit.unlockedGem();
        // execute depositAsset transfer from Centrifuge chain
        handleIncomingTransfer(amount / 10 ** 12);

        assertEq(
            ERC20Like(asset).balanceOf(address(escrow)),
            escrowBalanceBeforeWithdrawRequestASSET - amount / 10 ** 12 // normalize decimals
        );
        assertEq(
            ERC20Like(asset).balanceOf(address(conduit)),
            amount / 10 ** 12 // normalize decimals
        );
        assertEq(conduit.unlockedGem(), unlockedGem); // unlocked
            // GEM did not change, as the depositAsset is only burned on withdrawal

        // withdraw GEM from pool
        uint256 conduitBalanceBeforeWithdrawRequestUSDC = ERC20Like(USDC).balanceOf(address(conduit));
        uint256 withdrawalWalletBalanceBeforeWithdrawRequestUSDC =
            ERC20Like(USDC).balanceOf(address(conduit.withdrawal()));

        vm.prank(MATE);
        conduit.withdrawFromPool();

        assertEq(
            ERC20Like(USDC).balanceOf(address(escrow)),
            conduitBalanceBeforeWithdrawRequestUSDC - amount / 10 ** 12 // normalize decimals
        );
        assertEq(
            ERC20Like(USDC).balanceOf(conduit.withdrawal()),
            withdrawalWalletBalanceBeforeWithdrawRequestUSDC + amount / 10 ** 12 // normalize decimals
        );
    }

    function depositIntoPool(uint128 amount) internal {
        uint256 conduitBalanceBeforeDepositRequestUSDC = ERC20Like(USDC).balanceOf(address(conduit));
        uint256 externalBalanceBeforeDepositRequestUSDC = ERC20Like(USDC).balanceOf(self);
        uint256 escrowBalanceBeforeDepositRequestASSET = ERC20Like(asset).balanceOf(escrow);

        ERC20Like(USDC).transfer(address(conduit), amount / 10 ** 12);
        assertEq(conduit.unlockedGem(), amount / 10 ** 12); // unlocked
            // GEM in conduit
        vm.prank(MATE);
        conduit.depositIntoPool();

        assertEq(
            ERC20Like(USDC).balanceOf(address(conduit)),
            conduitBalanceBeforeDepositRequestUSDC + amount / 10 ** 12 // normalize decimals
        );
        assertEq(
            ERC20Like(USDC).balanceOf(self),
            externalBalanceBeforeDepositRequestUSDC - amount / 10 ** 12 // normalize decimals
        );
        assertEq(
            ERC20Like(asset).balanceOf(address(escrow)),
            escrowBalanceBeforeDepositRequestASSET + amount / 10 ** 12 // normalize decimals
        );
        // assert all USDC locked up as collateral for depositAssets
        assertEq(conduit.unlockedGem(), 0);
    }

    function deposit() internal {
        uint256 conduitBalanceBeforeDepositRequestUSDC = ERC20Like(USDC).balanceOf(address(conduit));
        uint256 conduitBalanceBeforeDepositRequestTrancheToken = ERC20Like(trancheToken).balanceOf(address(conduit));
        uint256 escrowBalanceBeforeDepositRequestASSET = ERC20Like(asset).balanceOf(escrow);
        uint256 depositAmount = ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT));

        vm.prank(MATE); // call as Ankura
        conduit.requestDeposit();

        assertEq(ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT)), 0);
        assertEq(
            ERC20Like(USDC).balanceOf(address(conduit)),
            conduitBalanceBeforeDepositRequestUSDC + depositAmount / 10 ** 12 // normalize decimals
        );
        assertEq(
            ERC20Like(asset).balanceOf(address(escrow)),
            escrowBalanceBeforeDepositRequestASSET + depositAmount / 10 ** 12 // normalize decimals
        );
        // execute epoch on Centrifuge chain and handle deposit
        handleDeposit(address(conduit), depositAmount);
        vm.prank(MATE);
        conduit.claimDeposit();
        assertEq(
            ERC20Like(trancheToken).balanceOf(address(conduit)),
            conduitBalanceBeforeDepositRequestTrancheToken + depositAmount
        );
        // assert all USDC locked up as collateral for depositAssets
        assertEq(conduit.unlockedGem(), 0);
    }

    function redeem(uint128 amount) internal {
        uint256 conduitBalanceBeforeRedeemRequestTrancheToken = ERC20Like(trancheToken).balanceOf(address(conduit));
        uint256 escrowBalanceBeforeRedeemRequestASSET = ERC20Like(asset).balanceOf(escrow);
        uint256 totalSupplyBeforeRedeemRequestASSET = ERC20Like(asset).totalSupply();
        uint256 unlockedGem = conduit.unlockedGem();

        vm.prank(MATE); // call as Ankura
        conduit.requestRedeem(amount);

        handleRedeem(address(conduit), amount / 10 ** 12); // execute epoch on Centrifuge chain and handle redeem
        vm.prank(MATE);
        conduit.claimRedeem();

        assertEq(
            ERC20Like(trancheToken).balanceOf(address(conduit)), conduitBalanceBeforeRedeemRequestTrancheToken - amount
        );
        assertEq(ERC20Like(asset).balanceOf(escrow), escrowBalanceBeforeRedeemRequestASSET - amount / 10 ** 12);
        assertEq(ERC20Like(asset).totalSupply(), totalSupplyBeforeRedeemRequestASSET - amount / 10 ** 12);
        assertEq(conduit.unlockedGem(), unlockedGem + amount / 10 ** 12); // make sure value of unlcoked GEM increased
            // in conduit
    }

    // helpers
    function makerDebt() internal returns (uint256) {
        bytes32 ilk = ilk();
        // get debt index
        (, uint256 art) = VatLike(VAT).urns(ilk, URN);

        // get accumulated interest rate index
        (, uint256 rateIdx,,,) = VatLike(VAT).ilks(ilk);

        // get interest rate per second and last interest rate update timestamp
        (uint256 duty, uint256 rho) = JugLike(JUG).ilks(ilk);

        // interest accumulation up to date
        if (block.timestamp == rho) {
            return art * rateIdx;
        }

        return rmul(art, rmul(rpow(JugLike(JUG).base() + duty, block.timestamp - rho, ONE), rateIdx));
        // calculate current debt (see jug.drip function in MakerDAO
    }

    function ilk() public view returns (bytes32 ilk_) {
        return GemJoinLike(UrnLike(URN).gemJoin()).ilk();
    }

    function addCurrency(address currency) internal {
        vm.assume(poolManager.currencyIdToAddress(currencyId) == address(0));

        vm.startPrank(gateway);
        poolManager.addCurrency(currencyId, currency);
        assertEq(poolManager.currencyIdToAddress(currencyId), currency);
        poolManager.allowInvestmentCurrency(poolId, currencyId);
        assertTrue(poolManager.isAllowedAsInvestmentCurrency(poolId, currency));
        vm.stopPrank();
    }

    function addTrancheTokenMember(address user) internal {
        vm.prank(gateway);
        poolManager.updateMember(poolId, trancheId, user, uint64(block.timestamp + 1000000));
    }

    function handleDeposit(address investor, uint256 depositAmount) internal {
        vm.prank(gateway);
        investmentManager.handleExecutedCollectInvest(
            poolId, trancheId, investor, currencyId, uint128(depositAmount), uint128(depositAmount), 0
        );
    }

    function handleRedeem(address investor, uint256 redeemAmount) internal {
        vm.prank(gateway);
        investmentManager.handleExecutedCollectRedeem(
            poolId, trancheId, investor, currencyId, uint128(redeemAmount), uint128(redeemAmount), 0
        );
    }

    function handleIncomingTransfer(uint256 amount) internal {
        vm.prank(gateway);
        poolManager.handleTransfer(currencyId, address(conduit), uint128(amount));
    }

    // Math helpers
    function rmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = safeMul(x, y) / ONE;
    }

    function safeMul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "safe-mul-failed");
    }

    function rpow(uint256 x, uint256 n, uint256 base) public pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}
