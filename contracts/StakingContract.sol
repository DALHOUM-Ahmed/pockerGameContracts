// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingContract is Ownable, ReentrancyGuard {
  struct Staker {
    uint256 amountStaked;
    uint256 lastUpdatedTournamentId;
    uint256 rewards;
  }

  mapping(address => Staker) public stakers;

  uint256 public totalStaked;
  uint256 public accumulatedRewardPerStakePerTournament;
  uint256 public currentTournamentId;

  uint256 public gapFillerPercentage; // in basis points (bps), e.g., 5000 for 50%
  address public gapFillerContractAddress;
  address public tournamentManagerAddress;

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount, uint256 reward);
  event RewardAdded(uint256 amount);
  event GapFillerPercentageUpdated(uint256 newPercentage);

  modifier onlyTournamentManager() {
    require(
      msg.sender == tournamentManagerAddress,
      "Only TournamentManager can call"
    );
    _;
  }

  constructor(
    address _gapFillerContractAddress,
    address _tournamentManagerAddress
  ) {
    gapFillerContractAddress = _gapFillerContractAddress;
    tournamentManagerAddress = _tournamentManagerAddress;
    gapFillerPercentage = 5000; // Default 50%
  }

  function setGapFillerPercentage(uint256 _percentage) external onlyOwner {
    require(_percentage <= 10000, "Percentage cannot exceed 100%");
    gapFillerPercentage = _percentage;
    emit GapFillerPercentageUpdated(_percentage);
  }

  function stake() external payable {
    require(msg.value > 0, "Must stake more than zero");

    uint256 gapAmount = (msg.value * gapFillerPercentage) / 10000;
    uint256 stakedAmount = msg.value - gapAmount;

    // Send gapAmount to GapFillerContract
    if (gapAmount > 0) {
      (bool success, ) = payable(gapFillerContractAddress).call{
        value: gapAmount
      }("");
      require(success, "Transfer to GapFillerContract failed");
    }

    updateRewards(msg.sender);

    stakers[msg.sender].amountStaked += stakedAmount;
    totalStaked += stakedAmount;
    stakers[msg.sender].lastUpdatedTournamentId = currentTournamentId;

    emit Staked(msg.sender, stakedAmount);
  }

  function withdraw() external nonReentrant {
    updateRewards(msg.sender);

    Staker storage staker = stakers[msg.sender];
    uint256 amount = staker.amountStaked;
    uint256 reward = staker.rewards;

    require(amount > 0, "No staked amount");

    staker.amountStaked = 0;
    staker.rewards = 0;

    totalStaked -= amount;

    uint256 totalAmount = amount + reward;
    (bool success, ) = payable(msg.sender).call{value: totalAmount}("");
    require(success, "Withdrawal failed");

    emit Withdrawn(msg.sender, amount, reward);
  }

  function updateRewards(address account) internal {
    Staker storage staker = stakers[account];
    uint256 tournamentsParticipated = currentTournamentId -
      staker.lastUpdatedTournamentId;

    if (tournamentsParticipated > 0 && staker.amountStaked > 0) {
      uint256 reward = (staker.amountStaked *
        accumulatedRewardPerStakePerTournament *
        tournamentsParticipated) / 1e18;
      staker.rewards += reward;
    }
    staker.lastUpdatedTournamentId = currentTournamentId;
  }

  // Function called by TournamentManager when a tournament ends
  function notifyTournamentEnded() external onlyTournamentManager {
    currentTournamentId += 1;
  }

  // Function to receive rewards from TournamentManager
  receive() external payable {
    require(msg.value > 0, "No reward sent");
    require(totalStaked > 0, "No stakers to distribute rewards to");

    // Calculate reward per stake per tournament
    uint256 rewardPerStake = (msg.value * 1e18) / (totalStaked);
    accumulatedRewardPerStakePerTournament += rewardPerStake;

    emit RewardAdded(msg.value);
  }

  // Owner can withdraw excess funds (if any)
  function withdrawExcess(uint256 amount) external onlyOwner {
    require(address(this).balance >= amount, "Insufficient funds");
    (bool success, ) = payable(owner()).call{value: amount}("");
    require(success, "Withdrawal failed");
  }
}
