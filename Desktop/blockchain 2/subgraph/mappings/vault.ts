import {BigInt, Bytes, log} from "@graphprotocol/graph-ts";
import {
  Deposit as DepositEvent,
  Withdraw as WithdrawEvent,
  Harvest as HarvestEvent,
} from "../generated/Vault/Vault";
import {
  VaultUser,
  DepositEvent as DepositEntity,
  WithdrawEvent as WithdrawEntity,
  HarvestEvent as HarvestEntity,
  VaultStats,
} from "../generated/schema";

const STATS_ID = Bytes.fromHexString("0x01");

function loadOrCreateUser(addr: Bytes): VaultUser {
  let user = VaultUser.load(addr);
  if (user == null) {
    user = new VaultUser(addr);
    user.shares = BigInt.zero();
    user.totalDeposited = BigInt.zero();
    user.totalWithdrawn = BigInt.zero();
    user.save();
  }
  return user as VaultUser;
}

function loadOrCreateStats(): VaultStats {
  let s = VaultStats.load(STATS_ID);
  if (s == null) {
    s = new VaultStats(STATS_ID);
    s.totalDeposited = BigInt.zero();
    s.totalWithdrawn = BigInt.zero();
    s.totalHarvested = BigInt.zero();
    s.depositCount = 0;
    s.withdrawCount = 0;
    s.harvestCount = 0;
  }
  return s as VaultStats;
}

export function handleDeposit(event: DepositEvent): void {
  let user = loadOrCreateUser(event.params.owner);
  user.shares = user.shares.plus(event.params.shares);
  user.totalDeposited = user.totalDeposited.plus(event.params.assets);
  user.save();

  let entity = new DepositEntity(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = user.id;
  entity.caller = event.params.sender;
  entity.assets = event.params.assets;
  entity.shares = event.params.shares;
  entity.blockNumber = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.txHash = event.transaction.hash;
  entity.save();

  let stats = loadOrCreateStats();
  stats.totalDeposited = stats.totalDeposited.plus(event.params.assets);
  stats.depositCount = stats.depositCount + 1;
  stats.save();
}

export function handleWithdraw(event: WithdrawEvent): void {
  let user = loadOrCreateUser(event.params.owner);
  user.shares = user.shares.minus(event.params.shares);
  user.totalWithdrawn = user.totalWithdrawn.plus(event.params.assets);
  user.save();

  let entity = new WithdrawEntity(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = user.id;
  entity.caller = event.params.sender;
  entity.receiver = event.params.receiver;
  entity.assets = event.params.assets;
  entity.shares = event.params.shares;
  entity.blockNumber = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.txHash = event.transaction.hash;
  entity.save();

  let stats = loadOrCreateStats();
  stats.totalWithdrawn = stats.totalWithdrawn.plus(event.params.assets);
  stats.withdrawCount = stats.withdrawCount + 1;
  stats.save();
}

export function handleHarvest(event: HarvestEvent): void {
  let entity = new HarvestEntity(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.yieldAmount = event.params.yieldAmount;
  entity.totalAssetsAfter = event.params.totalAssetsAfter;
  entity.blockNumber = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.save();

  let stats = loadOrCreateStats();
  stats.totalHarvested = stats.totalHarvested.plus(event.params.yieldAmount);
  stats.harvestCount = stats.harvestCount + 1;
  stats.save();

  log.info("Harvested {} (total assets after = {})", [
    event.params.yieldAmount.toString(),
    event.params.totalAssetsAfter.toString(),
  ]);
}
