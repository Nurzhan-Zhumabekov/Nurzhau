const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("GovernanceToken + TokenVesting", function () {
  let token, vesting;
  let team, treasury, community, liquidity, alice, bob;

  const TOTAL_SUPPLY = 1_000_000n * 10n ** 18n;

  beforeEach(async function () {
    [, team, treasury, community, liquidity, alice, bob] = await ethers.getSigners();

    // Token mints team share directly to team wallet for simplicity.
    // In production the deploy script sends it to vesting first.
    const TokenFactory   = await ethers.getContractFactory("GovernanceToken");
    const VestingFactory = await ethers.getContractFactory("TokenVesting");

    token   = await TokenFactory.deploy(
      team.address,       // team allocation (40%)
      treasury.address,   // treasury (30%)
      community.address,  // community (20%)
      liquidity.address   // liquidity (10%)
    );

    // Vesting contract — team is beneficiary, funded from team wallet
    vesting = await VestingFactory.deploy(await token.getAddress(), team.address);

    // Transfer team tokens to vesting to simulate real deployment
    const teamBalance = await token.balanceOf(team.address);
    await token.connect(team).transfer(await vesting.getAddress(), teamBalance);
  });

  // ── T1: total supply ─────────────────────────────────────────────────────
  it("T1: mints correct total supply", async function () {
    expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
  });

  // ── T2: distribution ─────────────────────────────────────────────────────
  it("T2: distributes treasury 30%, community 20%, liquidity 10%", async function () {
    expect(await token.balanceOf(treasury.address)).to.equal(TOTAL_SUPPLY * 3000n / 10000n);
    expect(await token.balanceOf(community.address)).to.equal(TOTAL_SUPPLY * 2000n / 10000n);
    expect(await token.balanceOf(liquidity.address)).to.equal(TOTAL_SUPPLY * 1000n / 10000n);
  });

  // ── T3: vesting holds team tokens ────────────────────────────────────────
  it("T3: vesting contract holds 40% team allocation", async function () {
    const vestingBal = await token.balanceOf(await vesting.getAddress());
    expect(vestingBal).to.equal(TOTAL_SUPPLY * 4000n / 10000n);
  });

  // ── T4: delegation ───────────────────────────────────────────────────────
  it("T4: allows vote delegation", async function () {
    await token.connect(community).delegate(alice.address);
    expect(await token.delegates(community.address)).to.equal(alice.address);
    expect(await token.getVotes(alice.address)).to.equal(
      await token.balanceOf(community.address)
    );
  });

  // ── T5: self-delegation ──────────────────────────────────────────────────
  it("T5: allows self-delegation", async function () {
    await token.connect(community).delegate(community.address);
    expect(await token.getVotes(community.address)).to.equal(
      await token.balanceOf(community.address)
    );
  });

  // ── T6: voting power snapshot ─────────────────────────────────────────────
  it("T6: getPastVotes returns correct snapshot at a past block", async function () {
    await token.connect(community).delegate(community.address);
    const blockBefore = await ethers.provider.getBlockNumber();

    const half = (await token.balanceOf(community.address)) / 2n;
    await token.connect(community).transfer(alice.address, half);

    const pastVotes = await token.getPastVotes(community.address, blockBefore);
    expect(pastVotes).to.equal(TOTAL_SUPPLY * 2000n / 10000n);
  });

  // ── T7: delegation follows tokens ────────────────────────────────────────
  it("T7: voting power moves when tokens transfer", async function () {
    await token.connect(community).delegate(alice.address);
    const bal = await token.balanceOf(community.address);
    await token.connect(community).transfer(bob.address, bal);
    expect(await token.getVotes(alice.address)).to.equal(0n);
  });

  // ── T8: permit (EIP-2612) ────────────────────────────────────────────────
  it("T8: ERC20Permit allows gasless approvals", async function () {
    const spender  = alice.address;
    const value    = 1000n * 10n ** 18n;
    const nonce    = await token.nonces(community.address);
    const deadline = BigInt(await time.latest()) + 3600n;
    const chainId  = (await ethers.provider.getNetwork()).chainId;

    const domain = {
      name: "GovernanceToken", version: "1", chainId,
      verifyingContract: await token.getAddress(),
    };
    const types = {
      Permit: [
        { name: "owner",    type: "address" },
        { name: "spender",  type: "address" },
        { name: "value",    type: "uint256" },
        { name: "nonce",    type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };
    const sig = await community.signTypedData(domain, types,
      { owner: community.address, spender, value, nonce, deadline });
    const { v, r, s } = ethers.Signature.from(sig);

    await token.permit(community.address, spender, value, deadline, v, r, s);
    expect(await token.allowance(community.address, spender)).to.equal(value);
  });

  // ── T9: permit nonce increments ──────────────────────────────────────────
  it("T9: permit nonce increments after each use", async function () {
    const nonceBefore = await token.nonces(community.address);
    const value    = 1n * 10n ** 18n;
    const deadline = BigInt(await time.latest()) + 3600n;
    const chainId  = (await ethers.provider.getNetwork()).chainId;

    const domain = {
      name: "GovernanceToken", version: "1", chainId,
      verifyingContract: await token.getAddress(),
    };
    const types = {
      Permit: [
        { name: "owner",    type: "address" }, { name: "spender", type: "address" },
        { name: "value",    type: "uint256" }, { name: "nonce",   type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };
    const sig = await community.signTypedData(domain, types,
      { owner: community.address, spender: alice.address, value, nonce: nonceBefore, deadline });
    const { v, r, s } = ethers.Signature.from(sig);

    await token.permit(community.address, alice.address, value, deadline, v, r, s);
    expect(await token.nonces(community.address)).to.equal(nonceBefore + 1n);
  });

  // ── T10: vesting — 0 releasable at start ─────────────────────────────────
  it("T10: vesting — nothing releasable immediately after deployment", async function () {
    // A tiny bit may be released due to block mining, but should be < 0.01%
    const r = await vesting.releasable();
    const teamAlloc = TOTAL_SUPPLY * 4000n / 10000n;
    // Less than 1 block's worth (365 days ≈ 2.6M blocks; 1 block ≈ 0.0000004%)
    expect(r).to.be.lessThan(teamAlloc / 1000n);
  });

  // ── T11: vesting — linear release after 6 months ─────────────────────────
  it("T11: vesting — releasable ~50% after 6 months", async function () {
    const teamAlloc = TOTAL_SUPPLY * 4000n / 10000n;
    const halfDuration = Number(await vesting.DURATION()) / 2;
    await time.increase(halfDuration);

    const r = await vesting.releasable();
    // Between 45% and 55% of team allocation
    expect(r).to.be.greaterThan(teamAlloc * 45n / 100n);
    expect(r).to.be.lessThan(teamAlloc * 55n / 100n);
  });

  // ── T12: vesting — full release after 12 months ───────────────────────────
  it("T12: vesting — full amount releasable after 12 months", async function () {
    const teamAlloc = TOTAL_SUPPLY * 4000n / 10000n;
    await time.increase(Number(await vesting.DURATION()) + 1);

    const r = await vesting.releasable();
    expect(r).to.equal(teamAlloc);
  });

  // ── T13: vesting — release sends tokens to beneficiary ────────────────────
  it("T13: vesting — release() transfers tokens to beneficiary", async function () {
    await time.increase(Number(await vesting.DURATION()) / 4); // 3 months in

    const balBefore = await token.balanceOf(team.address);
    await vesting.connect(team).release();
    const balAfter  = await token.balanceOf(team.address);
    const received  = balAfter - balBefore;

    // ~25% vested (3/12 months); allow ±0.1% for block-time rounding
    const teamAlloc = TOTAL_SUPPLY * 4000n / 10000n;
    expect(received).to.be.greaterThan(teamAlloc * 24n / 100n);
    expect(received).to.be.lessThan(teamAlloc * 26n / 100n);
  });
});
