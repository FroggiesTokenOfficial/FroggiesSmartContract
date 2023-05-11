// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Token is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    bool public isSwap;
    bool private isInternalTransaction;
    bool _inSwapAndLiquify;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    uint public lpThreshold = 0;
    uint public marketingThreshold = 1000000000000 * 10**18;
    uint public lpCurrentAmount;
    uint public marketingCurrentAmount;

    struct Fees {
        uint lp;
        uint burn;
        uint marketing;
    }

    Fees public buyFees = Fees(3, 3, 3);
    Fees public sellFees = Fees(3, 3, 3);

    uint256 public totalBuyFee = 9;
    uint256 public totalSellFee = 9;

    // mappings
    mapping (address => bool) public excludedFromFees;
    mapping(address => bool) public isPair;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SetPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    modifier lockTheSwap {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    constructor(address _router) ERC20("LLFR2", "LLFR2") {
        _mint(msg.sender, 100000000000000 * 10 ** decimals());

        address pancakeRouter = _router; // PancakeSwap router address for BSC
        IUniswapV2Router02 _pancakeV2Router = IUniswapV2Router02(pancakeRouter);
        IUniswapV2Factory factoryPancake = IUniswapV2Factory(_pancakeV2Router.factory());

        address _pancakeV2Pair = factoryPancake.createPair(address(this), _pancakeV2Router.WETH());

        uniswapV2Router = _pancakeV2Router;
        uniswapV2Pair = _pancakeV2Pair;

        _setPair(_pancakeV2Pair, true);

        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
    }

    receive() external payable {}

    function setPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "The PancakeSwap pair cannot be removed from isPair");
        _setPair(pair, value);
    }
    function _setPair(address pair, bool value) private onlyOwner {
        require(isPair[pair] != value, "Pair is already set to that value");
        isPair[pair] = value;
        emit SetPair(pair, value);
    }

    function swapAndLiquify(uint256 toSwapLiquidity) private lockTheSwap {
        isInternalTransaction = true;
        uint256 half = toSwapLiquidity.div(2);
        uint256 otherHalf = toSwapLiquidity.sub(half);
        uint256 swappedBNB = _swapTokensForBNB(half);
        addLiquidity(otherHalf, swappedBNB);
        isInternalTransaction = false;

        emit SwapAndLiquify(half, swappedBNB, otherHalf);
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    function _swapTokensForBNB(uint256 tokenAmount) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uint256 initialBalance = address(this).balance;
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 swappedBNB = address(this).balance.sub(initialBalance);

        return swappedBNB;
    }

    function _swapTokensForBNBSimple(uint256 tokenAmount) private {
        isInternalTransaction = true;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        isInternalTransaction = false;
    }

    // Custom transfer function with buy and sell fees and burn functionality
    function _transfer(address from, address to, uint256 amount) internal override {
        require(amount > 0, "Transfer amount must be greater than 0");
        uint256 trade_type = 0;
        uint256 remainingAmount = amount;
        if(!isInternalTransaction) {
            //buy
            if(isPair[from]) {
                if(!excludedFromFees[to]) {
                    trade_type = 1;
                }
            }
            //sell
            else if(isPair[to]) {
                if(!excludedFromFees[from]) {
                   trade_type = 2;
                }
            }
            // buy
            if(trade_type == 1 && !excludedFromFees[to]) {
                if (buyFees.lp > 0) {
                    uint256 lpAmount = remainingAmount.mul(buyFees.lp).div(100);
                    lpCurrentAmount = lpCurrentAmount.add(lpAmount);
                    remainingAmount = remainingAmount.sub(lpAmount);
                    super._transfer(from, address(this), lpAmount);
                }
                if (buyFees.marketing > 0) {
                    uint256 marketingAmount = remainingAmount.mul(buyFees.marketing).div(100);
                    marketingCurrentAmount = marketingCurrentAmount.add(marketingAmount);
                    remainingAmount = remainingAmount.sub(marketingAmount);
                    super._transfer(from, address(this), marketingAmount);
                }
                if (buyFees.burn > 0) {
                    uint256 burnAmount = remainingAmount.mul(buyFees.burn).div(100);
                    require(burnAmount <= balanceOf(from), "Insufficient balance to burn tokens");
                    remainingAmount = remainingAmount.sub(burnAmount);
                    super._burn(from, burnAmount);
                }
            }
            //sell
            else if(trade_type == 2 && !excludedFromFees[from]) {
                if (sellFees.lp > 0) {
                    uint256 lpAmount = remainingAmount.mul(sellFees.lp).div(100);
                    if (lpThreshold != 0 && (lpCurrentAmount.add(lpAmount) >= lpThreshold)) {
                        swapAndLiquify(lpCurrentAmount);
                        lpCurrentAmount = 0;  // Reset the lpCurrentAmount to 0 after swapAndLiquify is called
                        remainingAmount = remainingAmount.sub(lpAmount);
                    } else {
                        lpCurrentAmount = lpCurrentAmount.add(lpAmount);
                        remainingAmount = remainingAmount.sub(lpAmount);
                        super._transfer(from, address(this), lpAmount);
                    }
                }
                if (sellFees.marketing > 0) {
                    uint256 marketingAmount = remainingAmount.mul(sellFees.marketing).div(100);
                    if (isSwap && marketingThreshold != 0 && (marketingCurrentAmount.add(marketingAmount) >= marketingThreshold)) {
                        _swapTokensForBNBSimple(marketingCurrentAmount);
                        marketingCurrentAmount = 0; // Reset the marketingCurrentAmount to 0 because all tokens have been swapped
                        remainingAmount = remainingAmount.sub(marketingAmount);
                    } else {
                        marketingCurrentAmount = marketingCurrentAmount.add(marketingAmount);
                        remainingAmount = remainingAmount.sub(marketingAmount);
                        super._transfer(from, address(this), marketingAmount);
                    }
                }
                if (sellFees.burn > 0) {
                    uint256 burnAmount = remainingAmount.mul(sellFees.burn).div(100);
                    require(burnAmount <= balanceOf(from), "Insufficient balance to burn tokens");
                    remainingAmount = remainingAmount.sub(burnAmount);
                    super._burn(from, burnAmount);
                }
            }
            // no wallet to wallet tax
        }
        super._transfer(from, to, remainingAmount);
    }

    function setBuyTaxes(uint _lp, uint _burn, uint _marketing) external onlyOwner {
        totalBuyFee = _lp + _burn + _marketing;
        require(totalBuyFee <= 10, "Total buy fees cannot be more than 10%");
        buyFees = Fees(_lp, _burn, _marketing);
    }

    function setSellTaxes(uint _lp, uint _burn, uint _marketing) external onlyOwner {
        totalSellFee = _lp + _burn + _marketing;
        require(totalSellFee <= 10, "Total sell fees cannot be more than 10%");
        sellFees = Fees(_lp, _burn, _marketing);
    }

    function setLPThreshold(uint256 amount) public onlyOwner {
        uint256 currentTotalSupply = totalSupply();
        uint256 minLpThreshold = currentTotalSupply.mul(1).div(10000); // 0.01% of the current total token supply
        uint256 maxLpThreshold = currentTotalSupply.mul(5).div(100); // 5% of the current total token supply

        require(amount >= minLpThreshold && amount <= maxLpThreshold, "LP Threshold must be within the allowed range");
        lpThreshold = amount;
    }

    function setMarketingThreshold(uint256 amount) public onlyOwner{
        marketingThreshold = amount;
    }

    //set marketing auto-swap to WBNB
    function setMarketingSwap(bool check) public onlyOwner{
        isSwap = check;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        excludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function withdrawBNB(address payable to) external onlyOwner nonReentrant {
        require(address(this).balance > 0, "No BNB to withdraw");
        to.transfer(address(this).balance);
    }

    function withdrawMarketingTokens(address to, uint256 amount) public onlyOwner nonReentrant {
        require(marketingCurrentAmount >= amount, "Not enough tokens in marketing balance");
        IERC20(address(this)).transfer(to, amount);
        marketingCurrentAmount = marketingCurrentAmount - amount;
    }
}