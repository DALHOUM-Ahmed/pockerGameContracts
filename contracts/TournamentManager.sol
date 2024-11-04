// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./TicketNFT.sol";
import "./GapFillerContract.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract TournamentManager is AccessControl {
  bytes32 public constant TOURNAMENT_STARTER_ROLE =
    keccak256("TOURNAMENT_STARTER_ROLE");
  bytes32 public constant REWARD_DISTRIBUTOR_ROLE =
    keccak256("REWARD_DISTRIBUTOR_ROLE");
  bytes32 public constant CONTRACT_ROLE = keccak256("CONTRACT_ROLE");

  struct Tournament {
    uint256 id;
    address ticketNFTAddress;
    uint256 ticketPrice;
    uint256 minTickets;
    uint256 endDate;
    uint256 ticketsSold;
    uint256 totalCollected;
    bool ended;
  }

  uint256 public tournamentCounter;
  mapping(uint256 => Tournament) public tournaments;

  address public jackpotAddress;
  address public daoAddress;
  address public stackingAddress;

  uint256 public jackpotPercent; // in basis points (bps), e.g., 50 for 0.5%
  uint256 public daoPercent; // e.g., 150 for 1.5%
  uint256 public stackingPercent; // e.g., 100 for 1%

  address public gapFillerContractAddress;

  event TournamentStarted(
    uint256 indexed tournamentId,
    address ticketNFTAddress,
    uint256 ticketPrice,
    uint256 minTickets,
    uint256 endDate
  );
  event TicketsBought(
    uint256 indexed tournamentId,
    address buyer,
    uint256 amount
  );
  event TournamentEnded(uint256 indexed tournamentId);
  event RewardsDistributed(
    uint256 indexed tournamentId,
    address[] winners,
    uint256[] amounts
  );

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    jackpotPercent = 50; // 0.5%
    daoPercent = 150; // 1.5%
    stackingPercent = 100; // 1%
  }

  function setAddresses(
    address _jackpotAddress,
    address _daoAddress,
    address _stackingAddress
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    jackpotAddress = _jackpotAddress;
    daoAddress = _daoAddress;
    stackingAddress = _stackingAddress;
  }

  function setPercents(
    uint256 _jackpotPercent,
    uint256 _daoPercent,
    uint256 _stackingPercent
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    jackpotPercent = _jackpotPercent;
    daoPercent = _daoPercent;
    stackingPercent = _stackingPercent;
  }

  function setGapFillerContractAddress(
    address _gapFillerContractAddress
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    gapFillerContractAddress = _gapFillerContractAddress;
  }

  function startTournament(
    uint256 _ticketPrice,
    uint256 _minTickets,
    uint256 _endDate
  ) external onlyRole(TOURNAMENT_STARTER_ROLE) {
    require(_endDate > block.timestamp, "End date must be in the future");

    tournamentCounter += 1;
    Tournament storage t = tournaments[tournamentCounter];
    t.id = tournamentCounter;
    t.ticketPrice = _ticketPrice;
    t.minTickets = _minTickets;
    t.endDate = _endDate;

    TicketNFT ticketNFT = new TicketNFT(address(this), tournamentCounter);
    t.ticketNFTAddress = address(ticketNFT);

    emit TournamentStarted(
      t.id,
      t.ticketNFTAddress,
      t.ticketPrice,
      t.minTickets,
      t.endDate
    );
  }

  function buyTickets(uint256 tournamentId, uint256 amount) external payable {
    Tournament storage t = tournaments[tournamentId];
    require(block.timestamp < t.endDate, "Tournament has ended");
    require(amount > 0, "Amount must be greater than zero");
    require(msg.value == t.ticketPrice * amount, "Incorrect ETH amount sent");

    TicketNFT ticketNFT = TicketNFT(t.ticketNFTAddress);
    for (uint256 i = 0; i < amount; i++) {
      ticketNFT.mint(msg.sender);
    }

    uint256 jackpotShare = (msg.value * jackpotPercent) / 10000;
    uint256 daoShare = (msg.value * daoPercent) / 10000;
    uint256 stackingShare = (msg.value * stackingPercent) / 10000;
    uint256 remaining = msg.value - jackpotShare - daoShare - stackingShare;

    if (jackpotShare > 0) payable(jackpotAddress).transfer(jackpotShare);
    if (daoShare > 0) payable(daoAddress).transfer(daoShare);
    if (stackingShare > 0) payable(stackingAddress).transfer(stackingShare);

    t.totalCollected += remaining;
    t.ticketsSold += amount;

    emit TicketsBought(tournamentId, msg.sender, amount);
  }

  function endTournament(
    uint256 tournamentId
  ) external onlyRole(CONTRACT_ROLE) {
    Tournament storage t = tournaments[tournamentId];
    require(block.timestamp >= t.endDate, "Tournament not ended yet");
    require(!t.ended, "Tournament already ended");

    if (t.ticketsSold < t.minTickets) {
      uint256 unsoldTickets = t.minTickets - t.ticketsSold;
      uint256 totalCost = (t.ticketPrice *
        unsoldTickets *
        (10000 - jackpotPercent - daoPercent - stackingPercent)) / 10000; // 97% of ticket price per unsold ticket

      GapFillerContract gapFiller = GapFillerContract(
        payable(gapFillerContractAddress)
      );
      gapFiller.provideFunds(totalCost);

      t.totalCollected += totalCost;
      t.ticketsSold += unsoldTickets;
    }

    t.ended = true;

    emit TournamentEnded(tournamentId);
  }

  function distributeRewards(
    uint256 tournamentId,
    address[] calldata winners,
    uint256[] calldata amounts
  ) external onlyRole(REWARD_DISTRIBUTOR_ROLE) {
    Tournament storage t = tournaments[tournamentId];
    require(t.ended, "Tournament not ended");
    require(winners.length == amounts.length, "Arrays length mismatch");

    for (uint256 i = 0; i < winners.length; i++) {
      uint256 amount = amounts[i];
      require(amount <= t.totalCollected, "Insufficient funds");
      t.totalCollected -= amount;
      payable(winners[i]).transfer(amount);
    }

    emit RewardsDistributed(tournamentId, winners, amounts);
  }

  function withdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(address(this).balance >= amount, "Insufficient funds");

    (bool success, ) = payable(msg.sender).call{value: amount}("");
    require(success, "Withdrawal failed");
  }

  receive() external payable {}
}
