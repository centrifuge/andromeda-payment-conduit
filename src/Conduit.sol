// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface ERC20Like {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address user) external returns (uint256 amount);
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;
    function totalSupply() external returns (uint256);
}

interface OutputConduitLike {
    function push() external;
    function pick(address who) external;
    function hook(address psm) external;
}

interface InputConduitLike {
    function push() external;
}

interface ERC7540Like {
    function requestDeposit(uint256 assets, address receiver, address owner, bytes calldata data)
        external
        returns (uint256 requestId);
    function maxDeposit(address owner) external view returns (uint256 maxAssets);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function requestRedeem(uint256 shares, address receiver, address owner, bytes memory data)
        external
        returns (uint256);
    function maxRedeem(address owner) external view returns (uint256 maxShares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

interface PoolManagerLike {
    function transfer(address currency, bytes32 recipient, uint128 amount) external;
}

contract Conduit {
    address public immutable psm;
    ERC20Like public immutable dai;
    ERC20Like public immutable gem;

    // ERC20 locked in Centrifuge pool is a deposit token,
    // that does not hold any value itself. USDC is only held
    // by this payment conduit and can only be transferred out
    // to the fixed withdrawal address
    ERC20Like public immutable depositAsset;

    // Conduit that receives DAI and swaps it to USDC
    // to, mate = AndromedaPaymentConduit
    // https://github.com/makerdao/rwa-toolkit/blob/master/src/conduits/RwaSwapOutputConduit.sol
    OutputConduitLike public immutable outputConduit;

    // Conduits that receive USDC and swap it to DAI
    // https://github.com/makerdao/rwa-toolkit/blob/master/src/conduits/RwaSwapInputConduit.sol
    InputConduitLike public immutable urnConduit;
    InputConduitLike public immutable jarConduit;

    // Exchange agent
    address public withdrawal;

    // Centrifuge pool
    ERC7540Like public pool;
    PoolManagerLike public poolManager;
    bytes32 public depositRecipient;

    mapping(address => uint256) public wards;
    mapping(address => uint256) public can;
    mapping(address => uint256) public may;

    bool public unlockActive = false; // unlocks gem for mkr repayment

    /// -- Events --
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Hope(address indexed usr);
    event Nope(address indexed usr);
    event Mate(address indexed usr);
    event Hate(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address data1, address data2);
    event File(bytes32 indexed what, bytes32 data);

    constructor(
        address psm_,
        address dai_,
        address gem_,
        address depositAsset_,
        address outputConduit_,
        address urnConduit_,
        address jarConduit_
    ) {
        psm = psm_;
        dai = ERC20Like(dai_);
        gem = ERC20Like(gem_);
        depositAsset = ERC20Like(depositAsset_);

        outputConduit = OutputConduitLike(outputConduit_);
        urnConduit = InputConduitLike(urnConduit_);
        jarConduit = InputConduitLike(jarConduit_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "AndromedaPaymentConduit/not-authorized");
        _;
    }

    modifier onlyOperator() {
        require(can[msg.sender] == 1, "AndromedaPaymentConduit/not-operator");
        _;
    }

    modifier onlyMate() {
        require(may[msg.sender] == 1, "AndromedaPaymentConduit/not-mate");
        _;
    }

    /// -- Administration --
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function hope(address usr) external auth {
        can[usr] = 1;
        emit Hope(usr);
    }

    function nope(address usr) external auth {
        can[usr] = 0;
        emit Nope(usr);
    }

    function mate(address usr) external auth {
        may[usr] = 1;
        emit Mate(usr);
    }

    function hate(address usr) external auth {
        may[usr] = 0;
        emit Hate(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "withdrawal") {
            withdrawal = data;
        } else {
            revert("AndromedaPaymentConduit/unrecognised-param");
        }

        emit File(what, data);
    }

    function file(bytes32 what, address data1, address data2) external onlyOperator {
        if (what == "pool") {
            pool = ERC7540Like(data1);
            poolManager = PoolManagerLike(data2);
        } else {
            revert("AndromedaPaymentConduit/unrecognised-param");
        }

        emit File(what, data1, data2);
    }

    function file(bytes32 what, bytes32 data) external onlyOperator {
        if (what == "depositRecipient") {
            depositRecipient = data;
        } else {
            revert("AndromedaPaymentConduit/unrecognised-param");
        }

        emit File(what, data);
    }

    /// -- Invest --
    /// @notice Submit investment request for LTF tokens
    function requestDeposit() public onlyMate {
        // Get gem from outputConduit
        outputConduit.pick(address(this));
        outputConduit.hook(psm);
        outputConduit.push();

        // Mint deposit tokens
        uint256 amount = unlockedGem(); // only gem that is not used as collateral for already deposited depositAssets
            // can be used to deposit
        depositAsset.mint(address(this), amount);

        // Deposit in pool
        depositAsset.approve(address(pool), amount);
        pool.requestDeposit(amount, address(this), address(this), "");
    }

    /// @notice Transfer LTF tokens to this contract
    function claimDeposit() public {
        pool.deposit(pool.maxDeposit(address(this)), address(this));
    }

    /// -- Off-ramp --
    /// @notice Burn deposit tokens and withdraw gem
    function withdrawFromPool() public onlyMate {
        require(withdrawal != address(0), "AndromedaPaymentConduit/withdrawal-is-zero");
        require(depositAsset.balanceOf(address(this)) > 0, "AndromedaPaymentConduit/nothing-to-withdraw");

        uint256 amount = depositAsset.balanceOf(address(this));
        depositAsset.burn(address(this), amount);
        gem.transfer(withdrawal, amount); // use transfer here: transferFrom not working for USDC
    }

    /// -- On-ramp and Repay --
    /// @notice Submit redemption request for LTF tokens
    function requestRedeem(uint256 amount) public onlyMate {
        // claim tranchetokens from previously fulfilled orders, in case they haven't been claimed yet
        try pool.deposit(pool.maxDeposit(address(this)), address(this)) {} catch {} // can not call contract function

        pool.requestRedeem(amount, address(this), address(this), "");
    }

    /// @notice Lock deposit tokens in pool
    function depositIntoPool() public onlyMate {
        require(depositRecipient != "", "AndromedaPaymentConduit/deposit-recipient-is-zero");

        uint256 amount = unlockedGem();
        depositAsset.mint(address(this), amount);
        depositAsset.approve(address(poolManager), amount);
        poolManager.transfer(address(depositAsset), depositRecipient, _toUint128(amount));
    }

    /// @notice Claim and burn redeemed deposit tokens
    function claimRedeem() public onlyMate {
        uint256 claimableShares = pool.maxRedeem(address(this));
        uint256 redeemedAssets = pool.redeem(claimableShares, address(this), address(this));

        depositAsset.burn(address(this), redeemedAssets);
    }

    /// @notice Send gem as interest to jar
    function repayToJar(uint256 amount) public onlyMate {
        require(amount <= unlockedGem() || unlockActive, "AndromedaPaymentConduit/no-unlocked-gem-left");
        gem.transfer(address(jarConduit), amount);
        jarConduit.push();
    }

    /// @notice Send gem as principal to urn
    function repayToUrn(uint256 amount) public onlyMate {
        require(amount <= unlockedGem() || unlockActive, "AndromedaPaymentConduit/no-unlocked-gem-left");
        gem.transfer(address(urnConduit), amount);
        urnConduit.push();
    }

    /// @notice Unlocked gem = gem that is not used as collateral for depositAssets
    function unlockedGem() public returns (uint256) {
        if (depositAsset.totalSupply() >= gem.balanceOf(address(this))) {
            return 0;
        }
        return gem.balanceOf(address(this)) - depositAsset.totalSupply();
    }

    /// -- Fail-safes --
    function authMint(uint256 amount) public onlyMate {
        depositAsset.mint(address(this), amount);
    }

    function authBurn(uint256 amount) public onlyMate {
        depositAsset.burn(address(this), amount);
    }

    function unlock() public onlyMate {
        unlockActive = true;
    }

    function lock() public onlyMate {
        unlockActive = false;
    }

    /// -- Helpers --
    function _toUint128(uint256 _value) internal pure returns (uint128 value) {
        if (_value > type(uint128).max) {
            revert("AndromedaPaymentConduit/uint128-overflow");
        } else {
            value = uint128(_value);
        }
    }
}
