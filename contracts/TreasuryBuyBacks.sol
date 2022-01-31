// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract TreasuryBuyBacks is Ownable {

  address public treasuryFund;
  IERC20 public peg;
  IERC20 public native;
  IUniswapV2Router public router;
  address[] public toNative;
  address[] public toPeg;

  mapping(address => bool) public admins;

  constructor(address _treasuryFund, address _peg, address _native, IUniswapV2Router _router) public {
    treasuryFund = _treasuryFund;
    peg = IERC20(_peg);
    native = IERC20(_native);
    router = _router;
    toNative = [_peg, _native];
    toPeg = [_native, _peg];
  }

  modifier onlyAdmin() {
    require(msg.sender == owner() || admins[msg.sender], "Must be admin or owner");
    _;
  }

  function updateAdmins(address[] memory _admins, bool[] memory isAdmin) external onlyOwner {
    for (uint i; i < _admins.length; i++) {
      admins[_admins[i]] = isAdmin[i];
    }
  }

  function sellToNative(uint256 _amount) external onlyAdmin {
    peg.transferFrom(treasuryFund, address(this), _amount * 1e18);
    router.swapExactTokensForTokens(peg.balanceOf(address(this)), 0, toNative, treasuryFund, block.timestamp);
  }

  function nativeToPeg(uint256 _amount) external onlyAdmin {
    native.transferFrom(treasuryFund, address(this), _amount * 1e18);
    router.swapExactTokensForTokens(native.balanceOf(address(this)), 0, toPeg, treasuryFund, block.timestamp);
  }

}