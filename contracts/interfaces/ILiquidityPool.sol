// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityPool {
    event DepositedDPOOL(
        address indexed sender,
        IERC20 token,
        uint256 tokenAmount,
        uint256 aptMintAmount,
        uint256 tokenEthValue,
        uint256 totalEthValueLocked
    );
    event RedeemedDPOOL(
        address indexed sender,
        IERC20 token,
        uint256 redeemedTokenAmount,
        uint256 aptRedeemAmount,
        uint256 tokenEthValue,
        uint256 totalEthValueLocked
    );
    event AddLiquidityLocked();
    event AddLiquidityUnlocked();
    event RedeemLocked();
    event RedeemUnlocked();
    event AdminChanged(address);
    event KeyPairChanged(bytes32 keyPair);
    event PriceRegistryChanged(address priceRegistry);

    function addLiquidity(uint256 amount) external;

    function redeem(uint256 tokenAmount) external;
}