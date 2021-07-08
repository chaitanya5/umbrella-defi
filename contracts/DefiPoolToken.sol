//SPDX-License-Identifier: MIT

pragma solidity ^0.7.5;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/ILiquidityPool.sol";

import "@umb-network/toolbox/dist/contracts/IChain.sol";
import "@umb-network/toolbox/dist/contracts/IRegistry.sol";
import "@umb-network/toolbox/dist/contracts/lib/ValueDecoder.sol";


contract DefiPoolToken is ILiquidityPool, Ownable, ReentrancyGuard, Pausable, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant DEFAULT_POOL_TO_UNDERLYER_FACTOR = 1000;
    bool public addLiquidityLock;
    bytes32 public keyPair;
    bool public redeemLock;
    IERC20 public underlyer;
    IRegistry public priceRegistry;

    constructor (address _underlyer, address _priceRegistry, bytes32 _keyPair) 
    ERC20("Defi Pool Token", "DPOOL")
    {
        underlyer = IERC20(_underlyer); // Eg: DAI
        keyPair = _keyPair;             // DAI-BNB
        setRegistry(_priceRegistry);    // uses umbrella-network
    }

    receive() external payable {
        revert("DONT_SEND_ETHER");
    }

    /**
     * @notice Change umbrella price registry address in case of updates.
     * @param _priceRegistry address fo new registry contract.
     */
    function setRegistry(address _priceRegistry) public onlyOwner {
        require(_priceRegistry != address(0), "INVALID_AGG");
        priceRegistry = IRegistry(_priceRegistry);
        emit PriceRegistryChanged(address(_priceRegistry));
    }

    /**
     * @notice Change keyPair fetching from umbrella sdk.
     * @dev Never change keyPair as it should be fixed for a pair, only change if umbrella-sdk changes anytime.
     * @param _keyPair new keyPair.
     */
    function setKeyPair(bytes32 _keyPair) public onlyOwner {
        keyPair = _keyPair;         // DAI-BNB
        emit KeyPairChanged(keyPair);
    }

    /**
     * @notice Mint corresponding amount of DPOOL tokens for sent token amount.
     * @dev If no DPOOL tokens have been minted yet, fallback to a fixed ratio.
     */
    function addLiquidity(uint256 tokenAmt)
        external
        override
        nonReentrant
        whenNotPaused
    {
        require(!addLiquidityLock, "LOCKED");
        require(tokenAmt > 0, "AMOUNT_INSUFFICIENT");
        require(
            underlyer.allowance(msg.sender, address(this)) >= tokenAmt,
            "ALLOWANCE_INSUFFICIENT"
        );

        uint256 depositBnbValue = getBnbValueFromTokenAmount(tokenAmt);
        uint256 poolTotalBnbValue = getPoolTotalBnbValue();

        uint256 mintAmount =
            _calculateMintAmount(depositBnbValue, poolTotalBnbValue);

        _mint(msg.sender, mintAmount);
        underlyer.safeTransferFrom(msg.sender, address(this), tokenAmt);

        emit DepositedDPOOL(
            msg.sender,
            underlyer,
            tokenAmt,
            mintAmount,
            depositBnbValue,
            getPoolTotalBnbValue()
        );
    }

    function getPoolTotalBnbValue() public view returns (uint256) {
        return getBnbValueFromTokenAmount(underlyer.balanceOf(address(this)));
    }

    function getDPOOLBnbValue(uint256 amount) public view returns (uint256) {
        require(totalSupply() > 0, "INSUFFICIENT_TOTAL_SUPPLY");
        return (amount.mul(getPoolTotalBnbValue())).div(totalSupply());
    }

    function getBnbValueFromTokenAmount(uint256 amount)
        public
        view
        returns (uint256)
    {
        if (amount == 0) {
            return 0;
        }
        uint256 decimals = ERC20(address(underlyer)).decimals();
        
        return ((getTokenBnbPrice()).mul(amount)).div(10**decimals);    // bnbValue = (tokenBnbPrice * amount) / decimals
    }

    function getTokenAmountFromBnbValue(uint256 bnbValue)
        public
        view
        returns (uint256)
    {
        uint256 tokenBnbPrice = getTokenBnbPrice();
        uint256 decimals = ERC20(address(underlyer)).decimals();
        return ((10**decimals).mul(bnbValue)).div(tokenBnbPrice);       //tokenAmount = (bnbValue * decimals) / tokenBnbPrice
    }

    /**
     * @notice Fetch underlyer price in terms of BNB.
     * @dev Always check for timestamp in case of Umbrella FCD.
     */
    function getTokenBnbPrice() public view returns (uint256) {
        (uint256 price, uint256 timestamp) = _chain().getCurrentValue(keyPair);
        require(price > 0 && timestamp > 0, "price does not exists");
        return uint256(price);
    }

    function lockAddLiquidity() external onlyOwner {
        addLiquidityLock = true;
        emit AddLiquidityLocked();
    }

    function unlockAddLiquidity() external onlyOwner {
        addLiquidityLock = false;
        emit AddLiquidityUnlocked();
    }

    /**
     * @notice Redeems DPOOL amount for its underlying token amount.
     * @param dpoolAmount The amount of DPOOL tokens to redeem
     */
    function redeem(uint256 dpoolAmount)
        external
        override
        nonReentrant
        whenNotPaused
    {
        require(!redeemLock, "LOCKED");
        require(dpoolAmount > 0, "AMOUNT_INSUFFICIENT");
        require(dpoolAmount <= balanceOf(msg.sender), "BALANCE_INSUFFICIENT");

        uint256 redeemTokenAmt = getUnderlyerAmount(dpoolAmount);

        _burn(msg.sender, dpoolAmount);
        underlyer.safeTransfer(msg.sender, redeemTokenAmt);

        emit RedeemedDPOOL(
            msg.sender,
            underlyer,
            redeemTokenAmt,
            dpoolAmount,
            getBnbValueFromTokenAmount(redeemTokenAmt),
            getPoolTotalBnbValue()
        );
    }

    function lockRedeem() external onlyOwner {
        redeemLock = true;
        emit RedeemLocked();
    }

    function unlockRedeem() external onlyOwner {
        redeemLock = false;
        emit RedeemUnlocked();
    }

    function calculateMintAmount(uint256 tokenAmt)
        public
        view
        returns (uint256)
    {
        uint256 depositBnbValue = getBnbValueFromTokenAmount(tokenAmt);
        uint256 poolTotalBnbValue = getPoolTotalBnbValue();
        return _calculateMintAmount(depositBnbValue, poolTotalBnbValue); // amount of DPOOL
    }

    /**
     * @notice mint amount / total supply (before deposit)
     *          = token amount sent / contract token balance (before deposit)
     */
    function _calculateMintAmount(
        uint256 depositBnbAmount,
        uint256 totalBnbAmount
    ) internal view returns (uint256) {
        uint256 totalSupply = totalSupply();

        if (totalBnbAmount == 0 || totalSupply == 0) {
            return depositBnbAmount.mul(DEFAULT_POOL_TO_UNDERLYER_FACTOR);
        }

        return (depositBnbAmount.mul(totalSupply)).div(totalBnbAmount);
    }

    /**
     * @notice Get the underlying amount represented by DPOOL amount.
     * @param dpoolAmount The amount of DPOOL tokens
     * @return uint256 The underlying value of the DPOOL tokens
     */
    function getUnderlyerAmount(uint256 dpoolAmount)
        public
        view
        returns (uint256)
    {
        return getTokenAmountFromBnbValue(getDPOOLBnbValue(dpoolAmount));
    }

    /**
     * @notice Fetch the current umbrella chain address.
     * @dev umbrella Chain address keeps changing.
     */
    function _chain() internal view returns (IChain umbChain) {
        umbChain = IChain(priceRegistry.getAddress("Chain"));
        console.log("umbChain:");
        console.logAddress(address(umbChain));
    }
}