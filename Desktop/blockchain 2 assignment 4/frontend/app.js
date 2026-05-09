/**
 * DAO Governance dApp — app.js
 * Uses ethers.js v6 via CDN (loaded by index.html or a bundler).
 * Replace CONTRACT_ADDRESSES with your deployed addresses.
 */

// ── Contract addresses (update after deployment) ─────────────────────────────
const CONTRACT_ADDRESSES = {
  token:    "0x0000000000000000000000000000000000000001", // GovernanceToken
  governor: "0x0000000000000000000000000000000000000002", // MyGovernor
  timelock: "0x0000000000000000000000000000000000000003", // TimelockController
};

// ── ABIs (minimal — only what the frontend needs) ────────────────────────────
const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function getVotes(address) view returns (uint256)",
  "function delegate(address delegatee)",
  "function symbol() view returns (string)",
];

const GOVERNOR_ABI = [
  "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)",
  "function state(uint256 proposalId) view returns (uint8)",
  "function proposalVotes(uint256 proposalId) view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)",
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
  "function hasVoted(uint256 proposalId, address account) view returns (bool)",
  "function proposalSnapshot(uint256 proposalId) view returns (uint256)",
  "function proposalDeadline(uint256 proposalId) view returns (uint256)",
  "function votingDelay() view returns (uint256)",
  "function votingPeriod() view returns (uint256)",
  "function quorum(uint256 blockNumber) view returns (uint256)",
];

const STATE_LABELS = [
  "Pending", "Active", "Canceled", "Defeated",
  "Succeeded", "Queued", "Expired", "Executed",
];
const STATE_CLASS = [
  "pending", "active", "defeated", "defeated",
  "succeeded", "queued", "defeated", "executed",
];

// ── Globals ───────────────────────────────────────────────────────────────────
let provider, signer, userAddress;
let tokenContract, governorContract;
let knownProposalIds = [];

// ── Status bar ────────────────────────────────────────────────────────────────
function setStatus(msg, type = "ok") {
  const bar = document.getElementById("status-bar");
  bar.textContent = msg;
  bar.className = type;
}

// ── Connect wallet ────────────────────────────────────────────────────────────
async function connectWallet() {
  if (!window.ethereum) {
    setStatus("MetaMask not detected. Please install MetaMask.", "err");
    return;
  }
  try {
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer      = await provider.getSigner();
    userAddress = await signer.getAddress();

    tokenContract    = new ethers.Contract(CONTRACT_ADDRESSES.token,    TOKEN_ABI,    signer);
    governorContract = new ethers.Contract(CONTRACT_ADDRESSES.governor, GOVERNOR_ABI, signer);

    document.getElementById("connect-btn").textContent = userAddress.slice(0, 6) + "…" + userAddress.slice(-4);
    document.getElementById("wallet-address").textContent = userAddress;

    await refreshWalletInfo();
    setStatus("Wallet connected: " + userAddress, "ok");
  } catch (err) {
    setStatus("Connection failed: " + err.message, "err");
  }
}

// ── Refresh wallet info ───────────────────────────────────────────────────────
async function refreshWalletInfo() {
  if (!userAddress) return;
  try {
    const [balance, votes, delegate] = await Promise.all([
      tokenContract.balanceOf(userAddress),
      tokenContract.getVotes(userAddress),
      tokenContract.delegates(userAddress),
    ]);
    document.getElementById("token-balance").textContent =
      parseFloat(ethers.formatEther(balance)).toLocaleString() + " GOV";
    document.getElementById("voting-power").textContent =
      parseFloat(ethers.formatEther(votes)).toLocaleString() + " votes";
    document.getElementById("delegate-address").textContent =
      delegate === ethers.ZeroAddress ? "None" :
      delegate === userAddress ? "Self" :
      delegate.slice(0, 8) + "…" + delegate.slice(-6);
  } catch (err) {
    setStatus("Error loading wallet info: " + err.message, "err");
  }
}

// ── Delegate votes ────────────────────────────────────────────────────────────
async function delegateVotes() {
  if (!signer) { setStatus("Connect wallet first.", "err"); return; }
  const target = document.getElementById("delegate-input").value.trim() || userAddress;
  if (!ethers.isAddress(target)) { setStatus("Invalid address.", "err"); return; }
  try {
    setStatus("Sending delegation transaction…");
    const tx = await tokenContract.delegate(target);
    setStatus("Waiting for confirmation… tx: " + tx.hash);
    await tx.wait();
    await refreshWalletInfo();
    setStatus("Delegated to " + target + " ✓", "ok");
  } catch (err) {
    setStatus("Delegation failed: " + err.message, "err");
  }
}

// ── Load proposals ────────────────────────────────────────────────────────────
async function loadProposals() {
  if (!provider) { setStatus("Connect wallet first.", "err"); return; }
  setStatus("Loading proposals…");

  const list = document.getElementById("proposals-list");

  try {
    const filter   = governorContract.filters.ProposalCreated();
    const fromBlock = Math.max(0, (await provider.getBlockNumber()) - 100000);
    const events   = await governorContract.queryFilter(filter, fromBlock, "latest");

    if (events.length === 0) {
      list.innerHTML = '<div class="empty-state">No proposals found on this network.</div>';
      setStatus("No proposals found.", "ok");
      return;
    }

    list.innerHTML = "";
    for (const evt of events.slice().reverse()) {
      const args       = evt.args;
      const proposalId = args.proposalId;
      const card       = await buildProposalCard(proposalId, args);
      list.appendChild(card);
    }
    setStatus("Loaded " + events.length + " proposal(s).", "ok");
  } catch (err) {
    setStatus("Error loading proposals: " + err.message, "err");
    list.innerHTML = '<div class="empty-state">Failed to load proposals. Check contract addresses.</div>';
  }
}

// ── Build proposal card ───────────────────────────────────────────────────────
async function buildProposalCard(proposalId, args) {
  const [stateNum, votes] = await Promise.all([
    governorContract.state(proposalId),
    governorContract.proposalVotes(proposalId),
  ]);

  const hasVoted = userAddress
    ? await governorContract.hasVoted(proposalId, userAddress)
    : false;

  const stateLabel = STATE_LABELS[stateNum] ?? "Unknown";
  const stateClass = STATE_CLASS[stateNum] ?? "pending";
  const isActive   = stateNum === 1n || stateNum === 1;

  const totalVotes = votes.forVotes + votes.againstVotes + votes.abstainVotes;
  const pct = (v) => totalVotes === 0n ? 0 : Number((v * 1000n) / totalVotes) / 10;

  const desc   = args.description || "(no description)";
  const title  = desc.split("\n")[0].slice(0, 120);

  const card = document.createElement("div");
  card.className = "proposal-card";
  card.innerHTML = `
    <h3>${escHtml(title)}</h3>
    <div class="proposal-meta">
      <span class="badge ${stateClass}">${stateLabel}</span>
      <span style="font-size:0.78rem;color:#475569;">ID: ${proposalId.toString().slice(0, 10)}…</span>
    </div>
    <div class="vote-bar">
      <div class="for"     style="width:${pct(votes.forVotes)}%"></div>
      <div class="against" style="width:${pct(votes.againstVotes)}%"></div>
      <div class="abstain" style="width:${pct(votes.abstainVotes)}%"></div>
    </div>
    <div class="vote-counts">
      <span><span class="dot for"></span>For: ${fmt(votes.forVotes)}</span>
      <span><span class="dot against"></span>Against: ${fmt(votes.againstVotes)}</span>
      <span><span class="dot abstain"></span>Abstain: ${fmt(votes.abstainVotes)}</span>
    </div>
    ${isActive && !hasVoted ? `
    <div class="vote-btns">
      <button class="vote-btn for"     onclick="castVote('${proposalId}', 1)">✓ For</button>
      <button class="vote-btn against" onclick="castVote('${proposalId}', 0)">✗ Against</button>
      <button class="vote-btn abstain" onclick="castVote('${proposalId}', 2)">— Abstain</button>
    </div>` : isActive && hasVoted
      ? '<p style="font-size:0.8rem;color:#4ade80;margin-top:0.6rem;">✓ You have voted on this proposal.</p>'
      : ''}
  `;
  return card;
}

// ── Cast vote ─────────────────────────────────────────────────────────────────
async function castVote(proposalIdStr, support) {
  if (!signer) { setStatus("Connect wallet first.", "err"); return; }
  const proposalId = BigInt(proposalIdStr);
  const labels     = { 0: "Against", 1: "For", 2: "Abstain" };
  try {
    setStatus(`Voting ${labels[support]}…`);
    const tx = await governorContract.castVote(proposalId, support);
    setStatus("Waiting for confirmation… tx: " + tx.hash);
    await tx.wait();
    setStatus(`Vote cast: ${labels[support]} ✓`, "ok");
    await loadProposals();
  } catch (err) {
    setStatus("Vote failed: " + err.message, "err");
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function fmt(wei) {
  return parseFloat(ethers.formatEther(wei)).toLocaleString(undefined, { maximumFractionDigits: 0 });
}
function escHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Auto-connect if already authorized
window.addEventListener("load", async () => {
  if (window.ethereum?.selectedAddress) connectWallet();
});
