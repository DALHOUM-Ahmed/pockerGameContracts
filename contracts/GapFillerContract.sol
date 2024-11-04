// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";

contract GapFillerContract is Ownable {
  address public tournamentManager;

  constructor(address _tournamentManager) {
    tournamentManager = _tournamentManager;
  }

  function provideFunds(uint256 amount) external {
    require(
      msg.sender == tournamentManager,
      "Only tournament manager can call"
    );
    require(
      address(this).balance >= amount,
      "Insufficient funds in GapFillerContract"
    );

    (bool success, ) = payable(tournamentManager).call{value: amount}("");
    require(success, "Transfer to TournamentManager failed");
  }

  function withdraw(uint256 amount) external onlyOwner {
    require(address(this).balance >= amount, "Insufficient funds");

    (bool success, ) = payable(owner()).call{value: amount}("");
    require(success, "Withdrawal failed");
  }

  receive() external payable {}
}
