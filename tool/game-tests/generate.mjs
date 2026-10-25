import {writeFileSync} from 'node:fs';
import {GameEngine} from './engine.mjs';
const cases=[];
for (const seed of [0,1,42,4294967295]) {
  for (const mode of ['idle','periodic','every-tick','pilot']) {
    const engine=new GameEngine(seed), inputs=[], checkpoints=[];
    while (engine.tick<5400) {
      const flap=mode==='every-tick' || (mode==='periodic' && engine.tick%37===0) ||
        (mode==='pilot' && engine.cooldown===0 && engine.velocity>0 && engine.y>(engine.gates.find(g=>g.x+130000>=215000)?.center ?? 500000));
      if(flap) inputs.push(engine.tick);
      engine.step(flap);
      if(engine.tick===1 || engine.tick%120===0) checkpoints.push(engine.snapshot());
    }
    cases.push({seed,mode,inputs,checkpoints});
  }
}
writeFileSync('tool/game-tests/vectors.json',JSON.stringify(cases));
