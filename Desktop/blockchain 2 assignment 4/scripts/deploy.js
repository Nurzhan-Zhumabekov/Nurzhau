/**
 * Deploy script for the complete DAO governance system.
 * Deployment order:
 *   1. TimelockController (no dependencies)
 *   2. GovernanceToken → mints to team wallet, treasury (timelock), community, liquidity
 *   3. TokenVesting → receives team tokens from deployer
 *   4. MyGovernor → wired to token + timelock
 *   5. Box → owned by timelock
 *   6. Treasury → owned by timelock
 *   7. Configure timelock roles (proposer = governor, executor = anyone)
 */

const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  // ── Configuration ───────────────────────────────────────────────────────────
  const TIMELOCK_DELAY = 2 * 24 * 3600; // 2 days
  const COMMUNITY_WALLET = process.env.COMMUNITY_WALLET || deployer.address;
  const LIQUIDITY_WALLET = process.env.LIQUIDITY_WALLET || deployer.address;
  const TEAM_WALLET      = process.env.TEAM_WALLET      || deployer.address;

  // ── 1. TimelockController ────────────────────────────────────────────────────
  console.log("1. Deploying TimelockController...");
  const TL = await ethers.getContractFactory("TimelockController");
  const timelock = await TL.deploy(
    TIMELOCK_DELAY,
    [],               // proposers — set after governor
    [],               // executors
    deployer.address  // temp admin
  );
  await timelock.waitForDeployment();
  console.log("   TimelockController:", await timelock.getAddress());

  // ── 2. GovernanceToken ───────────────────────────────────────────────────────
  console.log("2. Deploying GovernanceToken...");
  const Token = await ethers.getContractFactory("GovernanceToken");
  const token = await Token.deploy(
    TEAM_WALLET,                       // 40% — team (will transfer to vesting)
    await timelock.getAddress(),       // 30% — treasury (held by timelock)
    COMMUNITY_WALLET,                  // 20% — community airdrop
    LIQUIDITY_WALLET                   // 10% — liquidity
  );
  await token.waitForDeployment();
  console.log("   GovernanceToken:", await token.getAddress());

  // ── 3. TokenVesting ──────────────────────────────────────────────────────────
  console.log("3. Deploying TokenVesting...");
  const Vesting = await ethers.getContractFactory("TokenVesting");
  const vesting = await Vesting.deploy(await token.getAddress(), TEAM_WALLET);
  await vesting.waitForDeployment();
  console.log("   TokenVesting:", await vesting.getAddress());

  // Transfer team tokens from TEAM_WALLET → vesting
  if (TEAM_WALLET === deployer.address) {
    const teamBal = await token.balanceOf(deployer.address);
    if (teamBal > 0n) {
      const tx = await token.transfer(await vesting.getAddress(), teamBal);
      await tx.wait();
      console.log("   Transferred team tokens to vesting:", ethers.formatEther(teamBal), "GOV");
    }
  }

  // ── 4. MyGovernor ────────────────────────────────────────────────────────────
  console.log("4. Deploying MyGovernor...");
  const Gov = await ethers.getContractFactory("MyGovernor");
  const governor = await Gov.deploy(await token.getAddress(), await timelock.getAddress());
  await governor.waitForDeployment();
  console.log("   MyGovernor:", await governor.getAddress());

  // ── 5. Box ───────────────────────────────────────────────────────────────────
  console.log("5. Deploying Box...");
  const Box = await ethers.getContractFactory("Box");
  const box = await Box.deploy(await timelock.getAddress());
  await box.waitForDeployment();
  console.log("   Box:", await box.getAddress());

  // ── 6. Treasury ──────────────────────────────────────────────────────────────
  console.log("6. Deploying Treasury...");
  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy(await timelock.getAddress());
  await treasury.waitForDeployment();
  console.log("   Treasury:", await treasury.getAddress());

  // ── 7. Configure Timelock Roles ──────────────────────────────────────────────
  console.log("7. Configuring timelock roles...");
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
  const ADMIN_ROLE    = await timelock.DEFAULT_ADMIN_ROLE();

  await (await timelock.grantRole(PROPOSER_ROLE, await governor.getAddress())).wait();
  console.log("   Governor set as proposer");

  await (await timelock.grantRole(EXECUTOR_ROLE, ethers.ZeroAddress)).wait();
  console.log("   Anyone can execute");

  await (await timelock.revokeRole(ADMIN_ROLE, deployer.address)).wait();
  console.log("   Admin role revoked from deployer");

  // ── Summary ──────────────────────────────────────────────────────────────────
  console.log("\n══════════════════════════════════════════════");
  console.log("DEPLOYMENT COMPLETE");
  console.log("══════════════════════════════════════════════");
  console.log("TimelockController :", await timelock.getAddress());
  console.log("GovernanceToken    :", await token.getAddress());
  console.log("TokenVesting       :", await vesting.getAddress());
  console.log("MyGovernor         :", await governor.getAddress());
  console.log("Box                :", await box.getAddress());
  console.log("Treasury           :", await treasury.getAddress());
  console.log("══════════════════════════════════════════════\n");

  console.log("Post-deployment verification checklist:");
  console.log("  □ token.totalSupply() == 1,000,000 GOV");
  console.log("  □ timelock.getMinDelay() == 172800 (2 days)");
  console.log("  □ governor.votingDelay() == 7200");
  console.log("  □ governor.votingPeriod() == 50400");
  console.log("  □ governor.proposalThreshold() == 10,000 GOV");
  console.log("  □ box.owner() == timelock address");
  console.log("  □ treasury.owner() == timelock address");
  console.log("  □ timelock has PROPOSER_ROLE → governor only");
  console.log("  □ timelock has EXECUTOR_ROLE → address(0) (anyone)");
  console.log("  □ deployer NO LONGER has DEFAULT_ADMIN_ROLE");
}

main()
  .then(() => process.exit(0))
  .catch((err) => { console.error(err); process.exit(1); });
