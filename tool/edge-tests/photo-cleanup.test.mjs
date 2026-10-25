import test from 'node:test';
import assert from 'node:assert/strict';
import {accountPhotos} from '../../supabase/functions/delete-account/photos.mjs';
const name='30000000-0000-4000-8000-000000000001.jpg';
function fake(files,error=null) {
  const calls=[];
  return {calls,admin:{storage:{from(bucket){calls.push(['bucket',bucket]);return {
    async list(prefix){calls.push(['list',prefix]);return {data:files,error};},
    async remove(paths){calls.push(['remove',paths]);return {error:null};},
  };}}}};
}
test('Cleanup derives all paths from the verified owner folder',async()=>{
  const f=fake([{name}]);await accountPhotos(f.admin).cleanup('owner');
  assert.deepEqual(f.calls,[['bucket','profile-photos'],['list','owner'],['remove',[`owner/${name}`]]]);
});
test('Unexpected nested or foreign paths fail closed',async()=>{
  const f=fake([{name:`../other/${name}`}]);
  await assert.rejects(()=>accountPhotos(f.admin).cleanup('owner'),/PHOTO_CLEANUP_FAILED/);
  assert.ok(!f.calls.some(x=>x[0]==='remove'));
});
test('Listing error never reports cleanup success',async()=>{
  const f=fake(null,true);await assert.rejects(()=>accountPhotos(f.admin).cleanup('owner'),/PHOTO_CLEANUP_FAILED/);
});
