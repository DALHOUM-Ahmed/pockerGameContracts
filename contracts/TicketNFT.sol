// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TicketNFT is ERC721 {
  address public tournamentManager;
  uint256 public tournamentId;
  uint256 public tokenIdCounter;

  constructor(
    address _tournamentManager,
    uint256 _tournamentId
  ) ERC721("Tournament Ticket", "TT") {
    tournamentManager = _tournamentManager;
    tournamentId = _tournamentId;
  }

  function mint(address to) external {
    require(
      msg.sender == tournamentManager,
      "Only tournament manager can mint"
    );
    tokenIdCounter += 1;
    _safeMint(to, tokenIdCounter);
  }
}
