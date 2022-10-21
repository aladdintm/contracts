// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interfaces/ISwapPair.sol";
import "../interfaces/IERC20Metadata.sol";

contract LpPool is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 totalDeposit;
        uint256 lastRewardBlock;  // Last block number that Tokens distribution occurs.
        uint256 accRewardsPerShare; // Accumulated RewardTokens per share, times 1e18.
    }

    struct PoolView {
        uint256 pid;
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        address token0;
        string symbol0;
        string name0;
        uint8 decimals0;
        address token1;
        string symbol1;
        string name1;
        uint8 decimals1;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
    }

    IERC20 public rewardToken;
    uint256 public maxStakingPerUser;

    uint256 public rewardPerBlock;

    uint256 public BONUS_MULTIPLIER = 1;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 private totalAllocPoint = 0;
    uint256 public startBlock;
    uint256 public bonusEndBlock;
    EnumerableSet.AddressSet private _pairs;
    mapping(address => uint256) public LpOfPid;
    EnumerableSet.AddressSet private _callers;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 rewards);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AddCaller(address user);
    event RemoveCaller(address user);

    constructor(
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _maxStakingPerUser
    ) public {
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        maxStakingPerUser = _maxStakingPerUser;
    }

    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    function add(uint256 _allocPoint, address _lpToken, bool _withUpdate) public onlyOwner {
        require(_lpToken != address(0), "LiquidityPool: _lpToken is the zero address");
        require(ISwapPair(_lpToken).token0() != address(0), "not lp");

        require(!EnumerableSet.contains(_pairs, _lpToken), "LpPool: lpToken is already added to the pool");
        EnumerableSet.add(_pairs, _lpToken);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                allocPoint: _allocPoint,
                totalDeposit: 0,
                lastRewardBlock: lastRewardBlock,
                accRewardsPerShare: 0
            })
        );
        LpOfPid[_lpToken] = poolInfo.length - 1;
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the number of reward token produced by each block
    function setRewardPerBlock(uint256 _newPerBlock) public onlyCaller {
        massUpdatePools();
        rewardPerBlock = _newPerBlock;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        massUpdatePools();
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setMaxStakingPerUser(uint256 amount) public onlyOwner {
        maxStakingPerUser = amount;
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid <= poolInfo.length - 1, "LpPool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e18).sub(user.rewardDebt);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid <= poolInfo.length - 1, "LpPool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(_amount.add(user.amount) <= maxStakingPerUser, 'exceed max stake');

        updatePool(_pid);
        
        uint256 reward;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                uint256 bal = rewardToken.balanceOf(address(this));
                if(bal >= pending) {
                    reward = pending;
                } else {
                    reward = bal;
                }
            }
        }

        if(_amount > 0) {
            uint256 oldBal = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(oldBal);

            user.amount = user.amount.add(_amount);
            pool.totalDeposit = pool.totalDeposit.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        if (reward > 0) {
            rewardToken.safeTransfer(address(msg.sender), reward);
        }
        
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: Insufficient balance");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
        
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDeposit = pool.totalDeposit.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        uint256 rewards;
        if(pending > 0) {
            uint256 bal = rewardToken.balanceOf(address(this));
            if(bal >= pending) {
                rewards = pending;
            } else {
                rewards = bal;
            }
        }
        rewardToken.safeTransfer(address(msg.sender), rewards);
        emit Withdraw(msg.sender, _amount, rewards);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        
        if(pool.totalDeposit >= user.amount) {
            pool.totalDeposit = pool.totalDeposit.sub(user.amount);
        } else {
            pool.totalDeposit = 0;
        }
        user.amount = 0;
        user.rewardDebt = 0;

        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    function getPoolView(uint256 pid) public view returns (PoolView memory) {
        require(pid < poolInfo.length, "LpPool: pid out of range");
        PoolInfo memory pool = poolInfo[pid];
        address lpToken = address(pool.lpToken);
        IERC20 token0 = IERC20(ISwapPair(lpToken).token0());
        IERC20 token1 = IERC20(ISwapPair(lpToken).token1());
        string memory symbol0 = IERC20Metadata(address(token0)).symbol();
        string memory name0 = IERC20Metadata(address(token0)).name();
        uint8 decimals0 = IERC20Metadata(address(token0)).decimals();
        string memory symbol1 = IERC20Metadata(address(token1)).symbol();
        string memory name1 = IERC20Metadata(address(token1)).name();
        uint8 decimals1 = IERC20Metadata(address(token1)).decimals();
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardPerBlock).div(totalAllocPoint);
        return
            PoolView({
                pid: pid,
                lpToken: lpToken,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardsPerShare,
                rewardsPerBlock: rewardsPerBlock,
                totalAmount: pool.totalDeposit,
                token0: address(token0),
                symbol0: symbol0,
                name0: name0,
                decimals0: decimals0,
                token1: address(token1),
                symbol1: symbol1,
                name1: name1,
                decimals1: decimals1
            });
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address lpToken, address account) public view returns (UserView memory) {
        uint256 pid = LpOfPid[lpToken];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingReward(pid, account);
        uint256 lpBalance = IERC20(lpToken).balanceOf(account);
        return
            UserView({
                stakedAmount: user.amount,
                unclaimedRewards: unclaimedRewards,
                lpBalance: lpBalance
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address lpToken;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            lpToken = address(poolInfo[i].lpToken);
            views[i] = getUserView(lpToken, account);
        }
        return views;
    }

     function addCaller(address user) public onlyOwner {
        require(user != address(0), "LpPool: user is the zero address");
        require(EnumerableSet.add(_callers, user), "PoolVault: add minter failed");

        emit AddCaller(user);
    }

    function delCaller(address user) public onlyOwner {
        require(user != address(0), "LpPool: user is the zero address");
        if (EnumerableSet.remove(_callers, user)) {
            emit RemoveCaller(user);
        }
    }

    function getCallers() public view returns (address[] memory ret) {
        uint len = EnumerableSet.length(_callers);
        ret = new address[](len);
        for (uint i = 0; i < len; ++i) {
            ret[i] = EnumerableSet.at(_callers, i);
        }
        return ret;
    }

    function isCaller(address account) public view returns (bool) {
        return EnumerableSet.contains(_callers, account);
    }

    modifier onlyCaller() {
        require(isCaller(msg.sender), "PoolVault: sender is not the caller");
        _;
    }
}