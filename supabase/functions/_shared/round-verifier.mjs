import {GameEngine, replay} from './game-engine.mjs';

export const INPUT_PROTOCOL = 'sky-hop-input-v1';
const TICKS = 5400;
const BATCH_TICKS = 120;

function requireValid(condition, reason) {
  if (!condition) throw new RangeError(reason);
}

// Internal domain function, NOT an HTTP handler. The caller must load room and
// receipts from trusted storage, authorize active participants, and lock/recheck
// the match before atomically recording any result/unlock. Never pass request
// JSON as room/receipts: receivedAtMs must be the database's initial receipt time.
export function verifyRound({room, streams, nowMs}) {
  requireValid(room != null && streams != null, 'round');
  requireValid(room.engineVersion === GameEngine.version, 'engine version');
  requireValid(room.inputProtocol === INPUT_PROTOCOL, 'input protocol');
  requireValid(room.status === 'awaiting_result', 'room status');
  requireValid(Number.isSafeInteger(room.startsAtMs) &&
    Number.isSafeInteger(room.endsAtMs) && room.endsAtMs === room.startsAtMs + 45000,
  'schedule');
  requireValid(Number.isSafeInteger(nowMs) && nowMs >= room.endsAtMs &&
    nowMs < room.endsAtMs + 15000, 'result window');
  requireValid(typeof room.id === 'string' && room.id.length > 0, 'room id');
  requireValid(Array.isArray(room.players) && room.players.length === 2 &&
    room.players.every(p => typeof p === 'string' && p.length > 0) &&
    room.players[0] !== room.players[1], 'players');
  requireValid(Array.isArray(streams) && streams.length === 2, 'streams');
  const results = room.players.map(playerId => {
    const matches = streams.filter(s => s?.playerId === playerId);
    requireValid(matches.length === 1, 'player stream');
    const stream = matches[0];
    requireValid(stream.roomId === room.id, 'stream room');
    requireValid(Array.isArray(stream.packets) &&
      stream.packets.length === TICKS / BATCH_TICKS, 'incomplete stream');
    const inputs = [];
    let previousReceipt = room.startsAtMs;
    for (let index = 0; index < stream.packets.length; index++) {
      const packet = stream.packets[index];
      const from = index * BATCH_TICKS;
      const through = from + BATCH_TICKS;
      requireValid(packet != null && packet.sequence === index &&
        packet.fromTick === from && packet.throughTick === through, 'packet sequence');
      requireValid(Number.isSafeInteger(packet.receivedAtMs) &&
        packet.receivedAtMs >= previousReceipt && packet.receivedAtMs <= nowMs,
      'receipt order');
      requireValid(packet.receivedAtMs >= room.startsAtMs + through * 1000 / 120 - 250 &&
        packet.receivedAtMs <= room.startsAtMs + from * 1000 / 120 + 5000,
      'receipt window');
      requireValid(Array.isArray(packet.flaps) && packet.flaps.length <= BATCH_TICKS,
        'packet inputs');
      let previous = from - 1;
      for (const tick of packet.flaps) {
        requireValid(Number.isInteger(tick) && tick > previous && tick >= from &&
          tick < through, 'input tick');
        inputs.push(tick);
        previous = tick;
      }
      previousReceipt = packet.receivedAtMs;
    }
    const state = replay(room.seed, inputs);
    return {playerId, score: state.score, hits: state.hits};
  });
  // Hits are diagnostic, not a tie breaker. Equal scores never unlock a field.
  const [a, b] = results;
  return {roomId: room.id, engineVersion: room.engineVersion,
    inputProtocol: INPUT_PROTOCOL, results,
    winnerId: a.score === b.score ? null : a.score > b.score ? a.playerId : b.playerId};
}
