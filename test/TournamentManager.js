const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Tournament System", function () {
  let TournamentManager;
  let tournamentManager;
  let GapFillerContract;
  let gapFillerContract;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let addr4;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
    TournamentManager = await ethers.getContractFactory("TournamentManager");
    tournamentManager = await TournamentManager.deploy();
    await tournamentManager.deployed();
    GapFillerContract = await ethers.getContractFactory("GapFillerContract");
    gapFillerContract = await GapFillerContract.deploy(
      tournamentManager.address
    );
    await gapFillerContract.deployed();
    await tournamentManager.setGapFillerContractAddress(
      gapFillerContract.address
    );
    const TOURNAMENT_STARTER_ROLE =
      await tournamentManager.TOURNAMENT_STARTER_ROLE();
    const REWARD_DISTRIBUTOR_ROLE =
      await tournamentManager.REWARD_DISTRIBUTOR_ROLE();
    const CONTRACT_ROLE = await tournamentManager.CONTRACT_ROLE();
    await tournamentManager.grantRole(TOURNAMENT_STARTER_ROLE, owner.address);
    await tournamentManager.grantRole(REWARD_DISTRIBUTOR_ROLE, owner.address);
    await tournamentManager.grantRole(CONTRACT_ROLE, owner.address);
    await tournamentManager.setAddresses(
      addr1.address,
      addr2.address,
      addr3.address
    );
  });

  it("Should start a tournament", async function () {
    const currentTime = (await ethers.provider.getBlock()).timestamp;
    const endDate = currentTime + 3600;
    const ticketPrice = ethers.utils.parseEther("1");
    const minTickets = 10;
    await tournamentManager.startTournament(ticketPrice, minTickets, endDate);
    const tournament = await tournamentManager.tournaments(1);
    expect(tournament.ticketPrice.eq(ticketPrice)).to.be.true;
    expect(tournament.minTickets.toString()).to.equal(minTickets.toString());
    expect(tournament.endDate.toString()).to.equal(endDate.toString());
    expect(tournament.ticketNFTAddress.toString()).to.not.equal(
      ethers.constants.AddressZero.toString()
    );
  });

  it("Should allow users to buy tickets and distribute percentages", async function () {
    const currentTime = (await ethers.provider.getBlock()).timestamp;
    const endDate = currentTime + 3600;
    const ticketPrice = ethers.utils.parseEther("1");
    const minTickets = 10;
    await tournamentManager.startTournament(ticketPrice, minTickets, endDate);

    const amount = 5;
    const totalCost = ticketPrice.mul(amount);

    const initialJackpotBalance = await ethers.provider.getBalance(
      addr1.address
    );
    const initialDAOBalance = await ethers.provider.getBalance(addr2.address);
    const initialStackingBalance = await ethers.provider.getBalance(
      addr3.address
    );

    const tx = await tournamentManager
      .connect(addr4)
      .buyTickets(1, amount, { value: totalCost });
    await tx.wait();

    const finalJackpotBalance = await ethers.provider.getBalance(addr1.address);
    const finalDAOBalance = await ethers.provider.getBalance(addr2.address);
    const finalStackingBalance = await ethers.provider.getBalance(
      addr3.address
    );

    const jackpotShare = totalCost.mul(50).div(10000);
    const daoShare = totalCost.mul(150).div(10000);
    const stackingShare = totalCost.mul(100).div(10000);

    expect(finalJackpotBalance.sub(initialJackpotBalance).eq(jackpotShare)).to
      .be.true;
    expect(finalDAOBalance.sub(initialDAOBalance).eq(daoShare)).to.be.true;
    expect(finalStackingBalance.sub(initialStackingBalance).eq(stackingShare))
      .to.be.true;

    const updatedTournament = await tournamentManager.tournaments(1);
    expect(updatedTournament.ticketsSold.toString()).to.equal(
      amount.toString()
    );
  });

  it("Should end tournament and invoke gap filler if minTickets not met", async function () {
    const currentTime = (await ethers.provider.getBlock()).timestamp;
    const endDate = currentTime + 100;
    const ticketPrice = ethers.utils.parseEther("1");
    const minTickets = 10;
    await tournamentManager.startTournament(ticketPrice, minTickets, endDate);
    await ethers.provider.send("evm_increaseTime", [200]);
    await ethers.provider.send("evm_mine", []);

    await addr4.sendTransaction({
      to: gapFillerContract.address,
      value: ethers.utils.parseEther("100"),
    });

    await tournamentManager.endTournament(1);
    const updatedTournament = await tournamentManager.tournaments(1);
    expect(updatedTournament.ended).to.be.true;
    expect(updatedTournament.ticketsSold.toString()).to.equal(
      minTickets.toString()
    );
  });

  it("Should distribute rewards correctly", async function () {
    const currentTime = (await ethers.provider.getBlock()).timestamp;
    const endDate = currentTime + 100;
    const ticketPrice = ethers.utils.parseEther("1");
    const minTickets = 1;
    await tournamentManager.startTournament(ticketPrice, minTickets, endDate);

    await tournamentManager
      .connect(addr4)
      .buyTickets(1, 1, { value: ticketPrice });

    await ethers.provider.send("evm_increaseTime", [200]);
    await ethers.provider.send("evm_mine", []);

    await tournamentManager.endTournament(1);

    const winners = [addr4.address];
    const amounts = [ethers.utils.parseEther("0.97")];

    const initialWinnerBalance = await ethers.provider.getBalance(
      addr4.address
    );

    const tx = await tournamentManager.distributeRewards(1, winners, amounts);
    const receipt = await tx.wait();
    // const gasUsed = receipt.gasUsed.mul(tx.gasPrice);

    const finalWinnerBalance = await ethers.provider.getBalance(addr4.address);
    const expectedBalanceChange = amounts[0];

    expect(finalWinnerBalance.sub(initialWinnerBalance).toString()).to.equal(
      expectedBalanceChange.toString()
    );

    const updatedTournament = await tournamentManager.tournaments(1);
    expect(updatedTournament.totalCollected.toString()).to.equal("0");
  });

  it("Should allow owner to withdraw funds from TournamentManager", async function () {
    const currentTime = (await ethers.provider.getBlock()).timestamp;
    const endDate = currentTime + 100;
    const ticketPrice = ethers.utils.parseEther("1");
    const minTickets = 1;
    await tournamentManager.startTournament(ticketPrice, minTickets, endDate);

    await tournamentManager
      .connect(addr4)
      .buyTickets(1, minTickets, { value: ticketPrice.mul(minTickets) });

    await ethers.provider.send("evm_increaseTime", [200]);
    await ethers.provider.send("evm_mine", []);

    await tournamentManager.endTournament(1);

    const contractBalance = await ethers.provider.getBalance(
      tournamentManager.address
    );

    const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

    const tx = await tournamentManager.withdraw(contractBalance);
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed.mul(tx.gasPrice);

    const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

    const expectedBalanceChange = contractBalance.sub(gasUsed);

    expect(finalOwnerBalance.sub(initialOwnerBalance).eq(expectedBalanceChange))
      .to.be.true;

    const finalContractBalance = await ethers.provider.getBalance(
      tournamentManager.address
    );
    expect(finalContractBalance.toString()).to.equal("0");
  });

  it("Should allow owner to withdraw funds from GapFillerContract", async function () {
    await addr4.sendTransaction({
      to: gapFillerContract.address,
      value: ethers.utils.parseEther("10"),
    });

    const contractBalance = await ethers.provider.getBalance(
      gapFillerContract.address
    );

    const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

    const withdrawAmount = ethers.utils.parseEther("5");

    const tx = await gapFillerContract.withdraw(withdrawAmount);
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed.mul(tx.gasPrice);

    const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

    const expectedBalanceChange = withdrawAmount.sub(gasUsed);

    expect(finalOwnerBalance.sub(initialOwnerBalance).eq(expectedBalanceChange))
      .to.be.true;

    const finalContractBalance = await ethers.provider.getBalance(
      gapFillerContract.address
    );
    expect(finalContractBalance.eq(contractBalance.sub(withdrawAmount))).to.be
      .true;
  });
});
