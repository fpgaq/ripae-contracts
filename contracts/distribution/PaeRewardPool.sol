// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract PaeRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. PAEs to distribute per block.
        uint256 lastRewardTime; // Last time that PAEs distribution occurs.
        uint256 accPaePerShare; // Accumulated PAEs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
        uint256 depositFee; // deposit fee, x / 10000, 2% max
    }

    IERC20 public pae;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when PAE mining starts.
    uint256 public poolStartTime;

    // The time when PAE mining ends.
    uint256 public poolEndTime;

    uint256 public paePerSecond = 0.005390664637 ether; // 170000 / (365 days * 24h * 60min * 60s)
    uint256 public runningTime = 365 days;
    uint256 public constant TOTAL_REWARDS = 170000 ether;

    uint256 constant MAX_DEPOSIT_FEE = 200; // 2%

    address public treasuryFund;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _pae,
        uint256 _poolStartTime,
        address _treasuryFund
    ) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_pae != address(0)) pae = IERC20(_pae);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
        treasuryFund = _treasuryFund;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "PaeRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "PaeRewardPool: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _depositFee
    ) public onlyOperator {
        require(_depositFee <= MAX_DEPOSIT_FEE, "deposit fee too high");
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accPaePerShare : 0,
            isStarted : _isStarted,
            depositFee: _depositFee
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's PAE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFee) public onlyOperator {
        require(_depositFee <= MAX_DEPOSIT_FEE, "deposit fee too high");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
        pool.depositFee = _depositFee;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(paePerSecond);
            return poolEndTime.sub(_fromTime).mul(paePerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(paePerSecond);
            return _toTime.sub(_fromTime).mul(paePerSecond);
        }
    }

    // View function to see pending PAEs on frontend.
    function pendingPAE(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPaePerShare = pool.accPaePerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _paeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accPaePerShare = accPaePerShare.add(_paeReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accPaePerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _paeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accPaePerShare = pool.accPaePerShare.add(_paeReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        deposit(msg.sender, _pid, _amount);
    }

    function deposit(address _to, uint256 _pid, uint256 _amount) public {
        address _from = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_to];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accPaePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safePaeTransfer(_to, _pending);
                emit RewardPaid(_to, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_from, address(this), _amount);
            uint256 depositFee = _amount.mul(pool.depositFee).div(10000);
            user.amount = user.amount.add(_amount.sub(depositFee));
            if (depositFee > 0) {
                pool.token.safeTransfer(treasuryFund, depositFee);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accPaePerShare).div(1e18);
        emit Deposit(_to, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accPaePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safePaeTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPaePerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe PAE transfer function, just in case if rounding error causes pool to not have enough PAEs.
    function safePaeTransfer(address _to, uint256 _amount) internal {
        uint256 _paeBal = pae.balanceOf(address(this));
        if (_paeBal > 0) {
            if (_amount > _paeBal) {
                pae.safeTransfer(_to, _paeBal);
            } else {
                pae.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setTreasuryFund(address _treasuryFund) external {
        require(msg.sender == treasuryFund, "!treasury");
        treasuryFund = _treasuryFund;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        // do not allow to drain core token (PAE or lps)
        require(_token != pae, "pae");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            require(_token != pool.token, "pool.token");
        }
        _token.safeTransfer(to, amount);
    }
}
