const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, mine } = require("@nomicfoundation/hardhat-network-helpers");

const TOTAL_SUPPLY   = 1_000_000n * 10n ** 18n;
const TIMELOCK_DELAY = 2 * 24 * 3600;   // 2 days in seconds
const VOTING_DELAY   = 7200;             // blocks (~1 day)
const VOTING_PERIOD  = 50400;            // blocks (~1 week)

describe("MyGovernor + TimelockController + Box + Treasury", function () {
  let token, governor, timelock, box, treasury;
  let owner, proposer, voter1, voter2, voter3, recipient;

  beforeEach(async function () {
    [owner, proposer, voter1, voter2, voter3, recipient] = await ethers.getSigners();

    // 1. TimelockController
    const TL = await ethers.getContractFactory("TimelockController");
    timelock  = await TL.deploy(TIMELOCK_DELAY, [], [], owner.address);

    // 2. GovernanceToken
    //    proposer  → 40% = 400K  (well above 1% = 10K proposal threshold)
    //    timelock  → 30% = 300K  (treasury share)
    //    voter1    → 20% = 200K
    //    voter2    → 10% = 100K
    const Token = await ethers.getContractFactory("GovernanceToken");
    token = await Token.deploy(
      proposer.address,
      await timelock.getAddress(),
      voter1.address,
      voter2.address
    );

    // 3. Governor
    const Gov = await ethers.getContractFactory("MyGovernor");
    governor  = await Gov.deploy(await token.getAddress(), await timelock.getAddress());

    // 4. Roles
    const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
    const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
    const ADMIN_ROLE    = await timelock.DEFAULT_ADMIN_ROLE();
    await timelock.connect(owner).grantRole(PROPOSER_ROLE, await governor.getAddress());
    await timelock.connect(owner).grantRole(EXECUTOR_ROLE, ethers.ZeroAddress);
    await timelock.connect(owner).revokeRole(ADMIN_ROLE,   owner.address);

    // 5. Box & Treasury
    const Box = await ethers.getContractFactory("Box");
    box = await Box.deploy(await timelock.getAddress());

    const Treas = await ethers.getContractFactory("Treasury");
    treasury = await Treas.deploy(await timelock.getAddress());

    // 6. Delegate votes
    await token.connect(proposer).delegate(proposer.address);
    await token.connect(voter1).delegate(voter1.address);
    await token.connect(voter2).delegate(voter2.address);
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  async function createProposal(target, calldata, description) {
    const tx = await governor.connect(proposer).propose(
      [target], [0], [calldata], description
    );
    const receipt = await tx.wait();
    for (const log of receipt.logs) {
      try {
        const parsed = governor.interface.parseLog(log);
        if (parsed.name === "ProposalCreated") return parsed.args.proposalId;
      } catch {}
    }
    throw new Error("ProposalCreated event not found");
  }

  async function passProposal(proposalId) {
    await mine(VOTING_DELAY + 1);
    await governor.connect(proposer).castVote(proposalId, 1); // For
    await governor.connect(voter1).castVote(proposalId, 1);   // For
    await mine(VOTING_PERIOD + 1);
  }

  async function queueAndExecute(target, calldata, description) {
    const descHash = ethers.id(description);
    await governor.queue([target], [0], [calldata], descHash);
    await time.increase(TIMELOCK_DELAY + 1);
    await governor.execute([target], [0], [calldata], descHash);
  }

  // ── T1: proposal is Pending after creation ──────────────────────────────
  it("T1: proposal state is Pending right after creation", async function () {
    const calldata = box.interface.encodeFunctionData("store", [1]);
    const id = await createProposal(await box.getAddress(), calldata, "T1");
    expect(await governor.state(id)).to.equal(0); // Pending
  });

  // ── T2: proposal becomes Active after voting delay ──────────────────────
  it("T2: proposal becomes Active after voting delay", async function () {
    const calldata = box.interface.encodeFunctionData("store", [2]);
    const id = await createProposal(await box.getAddress(), calldata, "T2");
    await mine(VOTING_DELAY + 1);
    expect(await governor.state(id)).to.equal(1); // Active
  });

  // ── T3: full lifecycle: propose → vote → queue → execute ────────────────
  it("T3: full lifecycle — Box.store(42)", async function () {
    const calldata   = box.interface.encodeFunctionData("store", [42]);
    const desc       = "T3: Store 42";
    const descHash   = ethers.id(desc);

    const id = await createProposal(await box.getAddress(), calldata, desc);
    await passProposal(id);

    expect(await governor.state(id)).to.equal(4); // Succeeded

    await governor.queue([await box.getAddress()], [0], [calldata], descHash);
    expect(await governor.state(id)).to.equal(5); // Queued

    await time.increase(TIMELOCK_DELAY + 1);
    await governor.execute([await box.getAddress()], [0], [calldata], descHash);
    expect(await governor.state(id)).to.equal(7); // Executed

    expect(await box.retrieve()).to.equal(42n);
  });

  // ── T4: vote delegation — delegatee votes on behalf of delegator ─────────
  it("T4: delegatee votes with full delegated power", async function () {
    await token.connect(voter2).delegate(voter3.address); // voter3 now wields voter2's 100K
    const voter2Bal = await token.balanceOf(voter2.address);

    const calldata = box.interface.encodeFunctionData("store", [4]);
    const id = await createProposal(await box.getAddress(), calldata, "T4");

    await mine(VOTING_DELAY + 1);
    await governor.connect(voter3).castVote(id, 1);

    const { forVotes } = await governor.proposalVotes(id);
    expect(forVotes).to.equal(voter2Bal);
  });

  // ── T5: quorum not met → Defeated ───────────────────────────────────────
  it("T5: proposal Defeated when no votes cast (quorum not met)", async function () {
    const calldata = box.interface.encodeFunctionData("store", [5]);
    const id = await createProposal(await box.getAddress(), calldata, "T5");
    await mine(VOTING_DELAY + 1);
    await mine(VOTING_PERIOD + 1);
    expect(await governor.state(id)).to.equal(3); // Defeated
  });

  // ── T6: Against majority → Defeated ─────────────────────────────────────
  it("T6: proposal Defeated when Against wins", async function () {
    const calldata = box.interface.encodeFunctionData("store", [6]);
    const id = await createProposal(await box.getAddress(), calldata, "T6");

    await mine(VOTING_DELAY + 1);
    // voter1 200K against, proposer 400K for → For wins (not a defeat scenario)
    // Use only voter1 against and no for votes
    await governor.connect(voter1).castVote(id, 0); // Against 200K
    await mine(VOTING_PERIOD + 1);
    // quorum met (200K > 4% of 1M = 40K), but for=0 against=200K → Defeated
    expect(await governor.state(id)).to.equal(3); // Defeated
  });

  // ── T7: Treasury ETH transfer via governance ─────────────────────────────
  it("T7: governance transfers ETH from treasury", async function () {
    await owner.sendTransaction({ to: await treasury.getAddress(), value: 10n ** 18n });

    const calldata = treasury.interface.encodeFunctionData("transferETH", [
      recipient.address, 5n * 10n ** 17n
    ]);
    const desc = "T7: Transfer 0.5 ETH";
    const id   = await createProposal(await treasury.getAddress(), calldata, desc);

    await passProposal(id);
    await queueAndExecute(await treasury.getAddress(), calldata, desc);

    const bal = await ethers.provider.getBalance(recipient.address);
    expect(bal).to.be.greaterThan(10n ** 18n * 10000n); // has more than 10000 ETH (initial)
  });

  // ── T8: change fee percentage via governance ─────────────────────────────
  it("T8: governance changes treasury fee percentage", async function () {
    const calldata = treasury.interface.encodeFunctionData("setFeePercentage", [200]);
    const desc = "T8: Set fee 2%";
    const id   = await createProposal(await treasury.getAddress(), calldata, desc);

    await passProposal(id);
    await queueAndExecute(await treasury.getAddress(), calldata, desc);

    expect(await treasury.feePercentage()).to.equal(200n);
  });

  // ── T9: cannot vote before voting delay ──────────────────────────────────
  it("T9: reverts when voting before voting delay", async function () {
    const calldata = box.interface.encodeFunctionData("store", [9]);
    const id = await createProposal(await box.getAddress(), calldata, "T9");
    await expect(governor.connect(voter1).castVote(id, 1))
      .to.be.revertedWithCustomError(governor, "GovernorUnexpectedProposalState");
  });

  // ── T10: cannot vote twice ────────────────────────────────────────────────
  it("T10: reverts on double vote", async function () {
    const calldata = box.interface.encodeFunctionData("store", [10]);
    const id = await createProposal(await box.getAddress(), calldata, "T10");
    await mine(VOTING_DELAY + 1);
    await governor.connect(voter1).castVote(id, 1);
    await expect(governor.connect(voter1).castVote(id, 1))
      .to.be.revertedWithCustomError(governor, "GovernorAlreadyCastVote");
  });

  // ── T11: cannot execute before timelock delay ─────────────────────────────
  it("T11: reverts when executing before timelock delay", async function () {
    const calldata = box.interface.encodeFunctionData("store", [11]);
    const desc     = "T11: Early execute";
    const id       = await createProposal(await box.getAddress(), calldata, desc);
    await passProposal(id);

    await governor.queue([await box.getAddress()], [0], [calldata], ethers.id(desc));
    // No time advance
    await expect(
      governor.execute([await box.getAddress()], [0], [calldata], ethers.id(desc))
    ).to.be.reverted;
  });

  // ── T12: below-threshold account cannot propose ───────────────────────────
  it("T12: reverts when proposer has insufficient voting power", async function () {
    const calldata = box.interface.encodeFunctionData("store", [0]);
    await expect(
      governor.connect(voter3).propose([await box.getAddress()], [0], [calldata], "T12")
    ).to.be.revertedWithCustomError(governor, "GovernorInsufficientProposerVotes");
  });

  // ── T13: abstain counts toward quorum but not for ─────────────────────────
  it("T13: abstain votes count toward quorum but not for-votes", async function () {
    const calldata = box.interface.encodeFunctionData("store", [13]);
    const id = await createProposal(await box.getAddress(), calldata, "T13");
    await mine(VOTING_DELAY + 1);
    await governor.connect(voter1).castVote(id, 2); // Abstain 200K
    await mine(VOTING_PERIOD + 1);

    const { forVotes, abstainVotes } = await governor.proposalVotes(id);
    expect(forVotes).to.equal(0n);
    expect(abstainVotes).to.be.greaterThan(0n);
    expect(await governor.state(id)).to.equal(3); // Defeated (quorum met, no for)
  });

  // ── T14: ERC-20 token transfer from treasury via governance ──────────────
  it("T14: governance transfers ERC-20 tokens from treasury", async function () {
    // Seed treasury with GOV tokens (from liquidity wallet)
    const seedAmt = 1000n * 10n ** 18n;
    await token.connect(voter2).transfer(await treasury.getAddress(), seedAmt);

    const calldata = treasury.interface.encodeFunctionData("transferERC20", [
      await token.getAddress(), recipient.address, seedAmt
    ]);
    const desc = "T14: Send tokens";
    const id   = await createProposal(await treasury.getAddress(), calldata, desc);

    await passProposal(id);
    await queueAndExecute(await treasury.getAddress(), calldata, desc);

    expect(await token.balanceOf(recipient.address)).to.equal(seedAmt);
  });

  // ── T15: proposal cannot be executed twice ────────────────────────────────
  it("T15: executed proposal cannot be executed again", async function () {
    const calldata = box.interface.encodeFunctionData("store", [15]);
    const desc     = "T15: Double execute";
    const id       = await createProposal(await box.getAddress(), calldata, desc);

    await passProposal(id);
    await queueAndExecute(await box.getAddress(), calldata, desc);

    await expect(
      governor.execute([await box.getAddress()], [0], [calldata], ethers.id(desc))
    ).to.be.revertedWithCustomError(governor, "GovernorUnexpectedProposalState");
  });
});
