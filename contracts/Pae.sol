// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "./interfaces/IDistributor.sol";
import "./owner/Operator.sol";

contract Pae is ERC20Burnable, Operator {
    using SafeMath for uint256;

    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 850000 ether;
    uint256 public constant INIT_TREASURY_FUND_POOL_ALLOCATION = 10000 ether; // for initial marketing
    uint256 public constant TREASURY_FUND_POOL_ALLOCATION = 45000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 95000 ether;

    uint256 public constant VESTING_DURATION = 125 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public treasuryFundRewardRate;
    uint256 public devFundRewardRate;

    address public treasuryFund;
    address public devFund;

    uint256 public treasuryFundLastClaimed;
    uint256 public devFundLastClaimed;
    bool public notifyDefFund = true;

    uint256 public farmingDistributed;

    constructor(uint256 _startTime, address _treasuryFund, address _devFund) public ERC20("Ripae", "PAE") {
        _mint(_treasuryFund, INIT_TREASURY_FUND_POOL_ALLOCATION);

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        treasuryFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        treasuryFundRewardRate = TREASURY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_treasuryFund != address(0), "Address cannot be 0");
        treasuryFund = _treasuryFund;
    }

    function setTreasuryFund(address _treasuryFund) external {
        require(msg.sender == _treasuryFund, "!treasury");
        treasuryFund = _treasuryFund;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function setNotifyDevFund(bool _notifyDefFund) external onlyOperator {
        notifyDefFund = _notifyDefFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (treasuryFundLastClaimed >= _now) return 0;
        _pending = _now.sub(treasuryFundLastClaimed).mul(treasuryFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to treasury and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && treasuryFund != address(0)) {
            _mint(treasuryFund, _pending);
            treasuryFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
            if (notifyDefFund) {
                IDistributor(devFund).distribute();
            }
        }
    }

    function distributeReward(address _farmingFund, uint256 _amount) external onlyOperator {
        farmingDistributed = farmingDistributed.add(_amount);
        require(farmingDistributed <= FARMING_POOL_REWARD_ALLOCATION, "!supply");
        require(_farmingFund != address(0), "!farmingFund");
        _mint(_farmingFund, _amount);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
