import {Address, BigInt, Bytes, ByteArray, crypto} from "@graphprotocol/graph-ts";
import {
  TransferSingle as TransferSingleEvent,
  TransferBatch as TransferBatchEvent,
  Crafted as CraftedEvent,
} from "../generated/GameItems/GameItems";
import {
  Player,
  ItemBalance,
  CraftEvent as CraftEntity,
} from "../generated/schema";

const ZERO_ADDRESS = Address.fromString("0x0000000000000000000000000000000000000000");

function loadOrCreatePlayer(addr: Address): Player {
  let id = Bytes.fromHexString(addr.toHexString());
  let player = Player.load(id);
  if (player == null) {
    player = new Player(id);
    player.totalCrafts = 0;
    player.save();
  }
  return player as Player;
}

function balanceId(player: Address, tokenId: BigInt): Bytes {
  let bytes = ByteArray.fromHexString(player.toHexString())
    .concat(ByteArray.fromBigInt(tokenId));
  return Bytes.fromByteArray(crypto.keccak256(bytes));
}

function loadOrCreateBalance(player: Address, tokenId: BigInt): ItemBalance {
  let id = balanceId(player, tokenId);
  let bal = ItemBalance.load(id);
  if (bal == null) {
    bal = new ItemBalance(id);
    let p = loadOrCreatePlayer(player);
    bal.player = p.id;
    bal.tokenId = tokenId;
    bal.balance = BigInt.zero();
  }
  return bal as ItemBalance;
}

function applyDelta(player: Address, tokenId: BigInt, delta: BigInt): void {
  if (player.equals(ZERO_ADDRESS)) return; // mint/burn legs
  let bal = loadOrCreateBalance(player, tokenId);
  bal.balance = bal.balance.plus(delta);
  bal.save();
}

export function handleTransferSingle(event: TransferSingleEvent): void {
  applyDelta(event.params.from, event.params.id, event.params.value.neg());
  applyDelta(event.params.to, event.params.id, event.params.value);
}

export function handleTransferBatch(event: TransferBatchEvent): void {
  let ids = event.params.ids;
  let values = event.params.values;
  for (let i = 0; i < ids.length; i++) {
    applyDelta(event.params.from, ids[i], values[i].neg());
    applyDelta(event.params.to, ids[i], values[i]);
  }
}

export function handleCrafted(event: CraftedEvent): void {
  let player = loadOrCreatePlayer(event.params.crafter);
  player.totalCrafts = player.totalCrafts + 1;
  player.save();

  let entity = new CraftEntity(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.crafter = player.id;
  entity.outputId = event.params.outputId;
  entity.amount = event.params.amount;
  entity.timestamp = event.block.timestamp;
  entity.txHash = event.transaction.hash;
  entity.save();
}
