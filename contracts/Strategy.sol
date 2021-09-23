// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import "../interfaces/BalancerV2.sol";
import "../interfaces/Uniswap.sol";

interface IName {
    function name() external view returns (string memory);
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IUniswapV2Router02 constant public uniswapRouter = IUniswapV2Router02(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
    IUniswapV2Router02 constant public sushiswapRouter = IUniswapV2Router02(address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F));
    IERC20 public constant weth = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 public router;

    IBalancerVault public balancerVault;
    IBalancerPool public bpt;
    IERC20[] public rewardTokens;
    IAsset[] public assets;
    uint256[] public minAmountsOut;
    bytes32 public balancerPoolId;
    uint8 public numTokens;
    uint8 public tokenIndex;
    uint256 public constant max = type(uint256).max;

    //1	    0.01%
    //5	    0.05%
    //10	0.1%
    //50	0.5%
    //100	1%
    //1000	10%
    //10000	100%
    uint256 public maxSlippageIn; // bips
    uint256 public maxSlippageOut; // bips
    uint256 public maxSingleDeposit;
    uint256 public minDepositPeriod; // seconds
    uint256 public lastDepositTime;
    uint256 public constant basisOne = 10000;
    bool internal isOriginal = true;

    constructor(
        address _vault,
        address _balancerVault,
        address _balancerPool,
        uint256 _maxSlippageIn,
        uint256 _maxSlippageOut,
        uint256 _maxSingleDeposit,
        uint256 _minDepositPeriod)
    public BaseStrategy(_vault){
        _initializeStrat(_vault, _balancerVault, _balancerPool, _maxSlippageIn, _maxSlippageOut, _maxSingleDeposit, _minDepositPeriod);
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _balancerVault,
        address _balancerPool,
        uint256 _maxSlippageIn,
        uint256 _maxSlippageOut,
        uint256 _maxSingleDeposit,
        uint256 _minDepositPeriod
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_vault, _balancerVault, _balancerPool, _maxSlippageIn, _maxSlippageOut, _maxSingleDeposit, _minDepositPeriod);
    }

    function _initializeStrat(
        address _vault,
        address _balancerVault,
        address _balancerPool,
        uint256 _maxSlippageIn,
        uint256 _maxSlippageOut,
        uint256 _maxSingleDeposit,
        uint256 _minDepositPeriod)
    internal {
        require(address(bpt) == address(0x0), "Strategy already initialized!");
        healthCheck = address(0xDDCea799fF1699e98EDF118e0629A974Df7DF012); // health.ychad.eth
        bpt = IBalancerPool(_balancerPool);
        balancerPoolId = bpt.getPoolId();
        balancerVault = IBalancerVault(_balancerVault);
        (address tokenAddress,) = balancerVault.getPool(balancerPoolId);
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(balancerPoolId);
        numTokens = uint8(tokens.length);
        assets = new IAsset[](numTokens);
        tokenIndex = type(uint8).max;
        for (uint8 i = 0; i < numTokens; i++) {
            if (tokens[i] == want) {
                tokenIndex = i;
            }
            assets[i] = IAsset(address(tokens[i]));
        }
        require(tokenIndex != type(uint8).max, "token not supported in pool!");

        maxSlippageIn = _maxSlippageIn;
        maxSlippageOut = _maxSlippageOut;
        maxSingleDeposit = _maxSingleDeposit.mul(10 ** uint256(ERC20(address(want)).decimals()));
        minAmountsOut = new uint256[](numTokens);
        minDepositPeriod = _minDepositPeriod;

        router = IUniswapV2Router02(uniswapRouter);
        want.safeApprove(address(balancerVault), max);
    }

    event Cloned(address indexed clone);

    function clone(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _balancerVault,
        address _balancerPool,
        uint256 _maxSlippageIn,
        uint256 _maxSlippageOut,
        uint256 _maxSingleDeposit,
        uint256 _minDepositPeriod
    ) external returns (address payable newStrategy) {
        require(isOriginal);

        bytes20 addressBytes = bytes20(address(this));

        assembly {
        // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(clone_code, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(add(clone_code, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            newStrategy := create(0, clone_code, 0x37)
        }

        Strategy(newStrategy).initialize(
            _vault, _strategist, _rewards, _keeper, _balancerVault, _balancerPool, _maxSlippageIn, _maxSlippageOut, _maxSingleDeposit, _minDepositPeriod
        );

        emit Cloned(newStrategy);
    }


    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return string(abi.encodePacked("SingleSidedBalancer ", bpt.symbol(), "Pool ", ERC20(address(want)).symbol()));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfPooled());
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit, uint256 _loss, uint256 _debtPayment){
        if (_debtOutstanding > 0) {
            (_debtPayment, _loss) = liquidatePosition(_debtOutstanding);
        }

        uint256 beforeWant = balanceOfWant();

        // 2 forms of profit. Incentivized rewards (BAL+other) and pool fees (want)
        collectTradingFees();
        sellRewards();

        uint256 afterWant = balanceOfWant();

        _profit = afterWant.sub(beforeWant);
        if (_profit > _loss) {
            _profit = _profit.sub(_loss);
            _loss = 0;
        } else {
            _loss = _loss.sub(_profit);
            _profit = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (now - lastDepositTime < minDepositPeriod) {
            return;
        }

        uint256 pooledBefore = balanceOfPooled();
        uint256[] memory maxAmountsIn = new uint256[](numTokens);
        uint256 amountIn = Math.min(maxSingleDeposit, balanceOfWant());
        maxAmountsIn[tokenIndex] = amountIn;

        if (maxAmountsIn[tokenIndex] > 0) {
            uint256[] memory amountsIn = new uint256[](numTokens);
            amountsIn[tokenIndex] = amountIn;
            bytes memory userData = abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0);
            IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);
            balancerVault.joinPool(balancerPoolId, address(this), address(this), request);

            uint256 pooledDelta = balanceOfPooled().sub(pooledBefore);
            uint256 joinSlipped = amountIn > pooledDelta ? amountIn.sub(pooledDelta) : 0;
            uint256 maxLoss = amountIn.mul(maxSlippageIn).div(basisOne);

            require(joinSlipped <= maxLoss, "Exceeded maxSlippageIn!");
            lastDepositTime = now;
        }
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss){
        if (estimatedTotalAssets() < _amountNeeded) {
            _liquidatedAmount = liquidateAllPositions();
            return (_liquidatedAmount, _amountNeeded.sub(_liquidatedAmount));
        }

        uint256 looseAmount = balanceOfWant();
        if (_amountNeeded > looseAmount) {
            uint256 toExitAmount = _amountNeeded.sub(looseAmount);

            _sellBptForExactToken(toExitAmount);

            _liquidatedAmount = Math.min(balanceOfWant(), _amountNeeded);
            _loss = _amountNeeded.sub(_liquidatedAmount);

            // enforce that amount exited didn't slip beyond our tolerance
            uint256 exitedAmount = _liquidatedAmount.sub(looseAmount);
            // just in case there's positive slippage
            uint256 exitSlipped = toExitAmount > exitedAmount ? toExitAmount.sub(exitedAmount) : 0;
            uint256 maxLoss = toExitAmount.mul(maxSlippageIn).div(basisOne);
            require(exitSlipped <= maxLoss, "Exceeded maxSlippageOut!");
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256 liquidated) {
        uint256 bpts = balanceOfBpt();
        if (bpts > 0) {
            // exit entire position for single token. Could revert due to single exit limit enforced by balancer
            bytes memory userData = abi.encode(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bpts, tokenIndex);
            IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
            balancerVault.exitPool(balancerPoolId, address(this), address(this), request);
        }
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        bpt.transfer(_newStrategy, balanceOfBpt());
        for (uint i = 0; i < rewardTokens.length; i++) {
            IERC20 token = rewardTokens[i];
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) {
                token.transfer(_newStrategy, balance);
            }
        }
    }

    function protectedTokens() internal view override returns (address[] memory){}

    function ethToWant(uint256 _amtInWei) public view override returns (uint256){
        if (_amtInWei == 0) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(want);

        uint256[] memory amounts = router.getAmountsOut(_amtInWei, path);
        return amounts[amounts.length - 1];
    }

    function tendTrigger(uint256 callCostInWei) public view override returns (bool) {
        return now.sub(lastDepositTime) > minDepositPeriod && balanceOfWant() > 0;
    }

    function harvestTrigger(uint256 callCostInWei) public view override returns (bool){
        bool hasRewards;
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            ERC20 rewardToken = ERC20(address(rewardTokens[i]));
            uint256 amount = rewardToken.balanceOf(address(this));

            uint decReward = rewardToken.decimals();
            uint decWant = ERC20(address(want)).decimals();
            uint decDiff = decReward > decWant ? decReward.sub(decWant) : 0;

            if (amount > 10 ** decDiff) {
                hasRewards = true;
                break;
            }
        }
        return super.harvestTrigger(callCostInWei) && hasRewards;
    }


    // HELPERS //
    function sellRewards() internal {
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            ERC20 rewardToken = ERC20(address(rewardTokens[i]));
            uint256 amount = rewardToken.balanceOf(address(this));

            uint decReward = rewardToken.decimals();
            uint decWant = ERC20(address(want)).decimals();
            uint decDiff = decReward > decWant ? decReward.sub(decWant) : 0;

            if (amount > 10 ** decDiff) {
                bool isWeth = want == weth || address(rewardToken) == address(weth);
                address[] memory path = new address[](isWeth ? 2 : 3);
                path[0] = address(rewardToken);
                if (isWeth) {
                    path[1] = address(want);
                } else {
                    path[1] = address(weth);
                    path[2] = address(want);
                }

                router.swapExactTokensForTokens(amount, 0, path, address(this), now);
            }
        }
    }

    function collectTradingFees() internal {
        uint256 total = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;
        if (total > debt) {
            uint256 profit = total.sub(debt);
            _sellBptForExactToken(profit);
        }
    }

    function balanceOfWant() public view returns (uint256 _amount){
        return want.balanceOf(address(this));
    }

    function balanceOfBpt() public view returns (uint256 _amount){
        return bpt.balanceOf(address(this));
    }

    function balanceOfReward(uint256 index) public view returns (uint256 _amount){
        return rewardTokens[index].balanceOf(address(this));
    }

    function balanceOfPooled() public view returns (uint256 _amount){
        uint256 totalWantPooled;
        (IERC20[] memory tokens,uint256[] memory totalBalances,uint256 lastChangeBlock) = balancerVault.getPoolTokens(balancerPoolId);
        for (uint8 i = 0; i < numTokens; i++) {
            uint256 tokenPooled = totalBalances[i].mul(balanceOfBpt()).div(bpt.totalSupply());
            if (tokenPooled > 0) {
                IERC20 token = tokens[i];
                if (token != want) {
                    IBalancerPool.SwapRequest memory request = _getSwapRequest(token, tokenPooled, lastChangeBlock);
                    // now denomated in want
                    tokenPooled = bpt.onSwap(request, totalBalances, i, tokenIndex);
                }
                totalWantPooled += tokenPooled;
            }
        }
        return totalWantPooled;
    }

    function _getSwapRequest(IERC20 token, uint256 amount, uint256 lastChangeBlock) internal view returns (IBalancerPool.SwapRequest memory request){
        return IBalancerPool.SwapRequest(IBalancerPool.SwapKind.GIVEN_IN,
            token,
            want,
            amount,
            balancerPoolId,
            lastChangeBlock,
            address(this),
            address(this),
            abi.encode(0)
        );
    }

    function _sellBptForExactToken(uint256 _amountTokenOut) internal {
        uint256[] memory amountsOut = new uint256[](numTokens);
        amountsOut[tokenIndex] = _amountTokenOut;
        bytes memory userData = abi.encode(IBalancerVault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, balanceOfBpt());
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        balancerVault.exitPool(balancerPoolId, address(this), address(this), request);
    }

    // for partnership rewards like Lido or airdrops
    function whitelistRewards(address _rewardToken) public onlyVaultManagers {
        IERC20 token = IERC20(_rewardToken);
        token.approve(address(uniswapRouter), max);
        token.approve(address(sushiswapRouter), max);
        rewardTokens.push(token);
    }

    function delistAllRewards() public onlyVaultManagers {
        for (uint i = 0; i < rewardTokens.length; i++) {
            rewardTokens[i].approve(address(uniswapRouter), 0);
            rewardTokens[i].approve(address(sushiswapRouter), 0);
        }
        IERC20[] memory noRewardTokens;
        rewardTokens = noRewardTokens;
    }

    function numRewards() public view returns (uint256 _num){
        return rewardTokens.length;
    }

    function setParams(uint256 _maxSlippageIn, uint256 _maxSlippageOut, uint256 _maxSingleDeposit, uint256 _minDepositPeriod) public onlyVaultManagers {
        require(_maxSlippageIn <= basisOne, "maxSlippageIn too high");
        maxSlippageIn = _maxSlippageIn;

        require(_maxSlippageOut <= basisOne, "maxSlippageOut too high");
        maxSlippageOut = _maxSlippageOut;

        maxSingleDeposit = _maxSingleDeposit;
        minDepositPeriod = _minDepositPeriod;
    }

    function switchDex(bool isUniswap) external onlyAuthorized {
        if (isUniswap) router = uniswapRouter;
        else router = sushiswapRouter;
    }

    receive() external payable {}
}
