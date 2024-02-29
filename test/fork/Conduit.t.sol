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
}

contract ForkTest is Test {
    Conduit public conduit;

    // MAKER
    address constant RWA_URN = 0xebFDaa143827FD0fc9C6637c3604B75Bbcfb7284; // ward on Maker contracts
    address constant URN = 0xebFDaa143827FD0fc9C6637c3604B75Bbcfb7284;
    address constant JAR = 0xc27C3D3130563C1171feCC4F76C217Db603997cf;
    address constant OUTPUT_CONDUIT = 0x1E86CB085f249772f7e7443631a87c6BDba2aCEb;
    address constant URN_CONDUIT = 0x4f7f76f31CE6Bb20809aaCE30EfD75217Fbfc217;
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

    // LIQUITY POOL
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
    address liquidityPool;

    address self;

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
        // deploy liquidityPool for depositAsset
        liquidityPool = poolManager.deployLiquidityPool(poolId, trancheId, asset);
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
        conduit.file("pool", liquidityPool, address(poolManager));
        // set ANDROMEDA addresses
        conduit.file("withdrawal", address(this)); // use deployer as withdrawel address for testing
        vm.prank(OPERATOR);
        conduit.file("depositRecipient", "DepositRecipient"); // use random String for testing
    }

    function testDeposit(uint128 amount) public {
        // amountAssumptions(amount); // fix later
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
    }

    function testWithdrawFromPool(uint128 amount) public {
        // amountAssumptions(amount); // fix later
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
    }

    function testDepositIntoPool(uint128 amount) public {
        // amountAssumptions(amount); // fix later
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
    }

    function testRedeem(uint128 amount) public {
        // amountAssumptions(amount); // fix later
        amount = 50000000000000000000000000;
        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
        redeem(amount);
    }

    function testRepayMaker(uint128 amount) public {
        // amountAssumptions(amount); // fix later
        amount = 50000000000000000000000000;
        // assert amount smaller debt
        // assert interest payment smaller debt

        drawGemFromVault(amount);
        deposit();
        withdrawFromPool(amount);
        depositIntoPool(amount);
        redeem(amount);

        vm.startPrank(MATE);
        conduit.repayToUrn((amount / 10 ** 12) / 2); // repay debt
        conduit.repayToJar((amount / 10 ** 12) / 2); // repay interest
        vm.stopPrank();
        // Todo: check Maker numbers 
    }

    // function testEmergencyRepayMaker() public {
    // }

    // draw from vault
    function drawGemFromVault(uint128 amount) internal {
        uint256 outputConduitBalanceBeforeDrawDAI = ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT));
        vm.prank(MATE); // call as Ankura
        UrnLike(RWA_URN).draw(amount); // draw DAI from vault in case output_conduit has no DAI
        assertEq(ERC20Like(DAI).balanceOf(address(OUTPUT_CONDUIT)), amount + outputConduitBalanceBeforeDrawDAI);
    }

    function withdrawFromPool(uint128 amount) internal {
        uint256 escrowBalanceBeforeWithdrawRequestASSET = ERC20Like(asset).balanceOf(escrow);
        // execute depositAsset transfer from Centrifuge chain
        handleIncomingTransfer(amount / 10 ** 12);
        assertEq(
            ERC20Like(asset).balanceOf(address(escrow)),
            escrowBalanceBeforeWithdrawRequestASSET - amount / 10 ** 12 // normalize decimals
        );
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
    }

    function redeem(uint128 amount) internal {
        uint256 conduitBalanceBeforeRedeemRequestTrancheToken = ERC20Like(trancheToken).balanceOf(address(conduit));
        uint256 escrowBalanceBeforeRedeemRequestASSET = ERC20Like(asset).balanceOf(escrow);

        vm.prank(MATE); // call as Ankura
        conduit.requestRedeem(amount);

        handleRedeem(address(conduit), amount / 10 ** 12); // execute epoch on Centrifuge chain and handle redeem
        vm.prank(MATE);
        conduit.claimRedeem();

        assertEq(
            ERC20Like(trancheToken).balanceOf(address(conduit)), conduitBalanceBeforeRedeemRequestTrancheToken - amount
        );
        assertEq(ERC20Like(asset).balanceOf(escrow), escrowBalanceBeforeRedeemRequestASSET - amount / 10 ** 12);
    }

    // helpers
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

    // general assertions
    function usdcCollateralAssertions() internal {
        // assertEq(restrictionManager.values_address("transfer_from"), from);
    }

    function amountAssumptions(uint256 amount) internal {
        vm.assume(amount >= 10000000000000000000000000 && amount <= 50000000000000000000000000); // Todo: anable
            // fuzzing, bit tricky because of vault constraints regarding ceiling
    }
}
