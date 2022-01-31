// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDistributor.sol";
import "./interfaces/IERC20.sol";

contract DevFund is Ownable, IDistributor {

  struct Allocation {
    address account;
    uint256 points;
  }

  Allocation[] public allocations;
  uint256 public totalPoints;

  IERC20[] public tokens;

  constructor(address[] memory accounts, uint256[] memory points) public {
    for (uint256 a = 0; a < accounts.length; a++) {
      allocations.push(Allocation({
      account : accounts[a],
      points : points[a]
      }));
      totalPoints += points[a];
    }
  }

  function addToken(IERC20 token) external onlyOwner {
    tokens.push(token);
  }

  function distribute() override external {
    for (uint256 t; t < tokens.length; t++) {
      IERC20 token = tokens[t];
      uint256 balance = token.balanceOf(address(this));
      if (balance > 0) {
        for (uint256 a; a < allocations.length; a++) {
          token.transfer(allocations[a].account, balance * allocations[a].points / totalPoints);
        }
      }
    }
  }

  function addAllocation(address account, uint256 points) external onlyOwner {
    allocations.push(Allocation({
    account: account,
    points: points
    }));
    totalPoints += points;
  }

  function removeAllocation(address account) external onlyOwner {
    for (uint256 a = 0; a < allocations.length; a++) {
      if (allocations[a].account == account) {
        totalPoints -= allocations[a].points;
        allocations[a] = allocations[allocations.length - 1];
        allocations.pop();
        break;
      }
    }
  }

  function setAllocationPoints(address account, uint256 points) external onlyOwner {
    for (uint256 a = 0; a < allocations.length; a++) {
      if (allocations[a].account == account) {
        totalPoints = totalPoints - allocations[a].points + points;
        allocations[a].points = points;
      }
    }
  }

  function call(address payable _to, uint256 _value, bytes calldata _data) external payable onlyOwner returns (bytes memory) {
    (bool success, bytes memory result) = _to.call{value: _value}(_data);
    require(success, "external call failed");
    return result;
  }

}