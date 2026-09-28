import test from 'node:test';
import assert from 'node:assert/strict';
import { encode } from '@auth/core/jwt';
import { openStore, createUser, issue, pruneStore } from '../store.mjs';
import { createApp } from '../app.mjs';
import { sessionIdentity } from '../session.mjs';

const secret = 'synthetic-auth-secret-at-least-32-characters';
const household = 'synthetic-household-secret-32-characters';
const healthToken = 'synthetic-health-export-secret-32-characters';
async function fixture(t) {
  const db = openStore(':memory:');
  for (const id of ['owner','family','friend']) createUser(db, { id, email: `${id}@example.test`, name: id, family: 'one' });
  db.exec("UPDATE users SET access_version='1'");
  const tokens = Object.fromEntries(['owner','family','friend'].map(id => [id, issue(db,id,'device','Synthetic',3600000)]));
  const grants = new Map(['owner','family','friend'].map(id => [`${id}@example.test`, {allowed:id!=='friend',version:'1'}]));
  let down = false;
  const app = createApp(db, { origin:'https://example.test', authSecret:secret, serviceOwner:'owner@example.test',
    householdToken:household, serviceToken:healthToken, policyUrl:'http://127.0.0.1/policy', policyToken:'p'.repeat(32),
    fetchImpl:async url => down ? new Response('',{status:503}) : Response.json(grants.get(new URL(url).searchParams.get('email'))) });
  await new Promise(resolve => app.listen(0,'127.0.0.1',resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const request = async (path, {token=tokens.family,method='GET',body,cookie}={}) => {
    const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/${path}`, {method,
      headers:{...(cookie ? {Cookie:cookie,Origin:'https://example.test'} : {Authorization:`Bearer ${token}`}), 'Content-Type':'application/json'},
      ...(body === undefined ? {} : {body:JSON.stringify(body)})});
    return {status:response.status,body:await response.json()};
  };
  const browser = async (id, extra={}) => '__Secure-authjs.session-token='+await encode({secret,salt:'__Secure-authjs.session-token',maxAge:3600,token:{email:`${id}@example.test`,...extra}});
  const state = async () => (await request('household?limit=1',{token:household})).body;
  return {db,tokens,grants,request,browser,state,setDown:v=>{down=v;}};
}

test('live permissions deny a Friend, stale browser and old device, including remove/re-add', async t => {
  const f=await fixture(t);
  assert.equal((await f.request('me',{token:f.tokens.friend})).status,403);
  assert.equal((await f.request('pair-code',{method:'POST',body:{},cookie:await f.browser('friend')})).status,403);
  assert.equal((await f.request('me')).status,200);
  f.grants.set('family@example.test',{allowed:true,version:'3'}); // removal and restoration happened between requests
  assert.equal((await f.request('me')).status,401);
  assert.equal(f.db.prepare("SELECT count(*) n FROM credentials WHERE user_id='family'").get().n,0);
  const pair=await f.request('pair-code',{method:'POST',body:{},cookie:await f.browser('family')});
  assert.equal(pair.status,200);
  f.grants.set('family@example.test',{allowed:false,version:'4'});
  assert.equal((await f.request('pair',{method:'POST',body:{code:pair.body.code,label:'old code'}})).status,403);
});

test('authority outage fails closed without deleting valid credentials', async t => {
  const f=await fixture(t); f.setDown(true);
  assert.equal((await f.request('me')).status,503);
  assert.equal(f.db.prepare("SELECT count(*) n FROM credentials WHERE user_id='family'").get().n,1);
  f.setDown(false); assert.equal((await f.request('me')).status,200);
});

test('registration-only JWE is never an ordinary companion session', async t => {
  const f=await fixture(t), cookie=await f.browser('family',{registrant:true,registerUntil:Date.now()+60000});
  assert.equal(await sessionIdentity(cookie,secret),null);
  assert.equal((await f.request('me',{cookie})).status,401);
  assert.equal(await sessionIdentity(await f.browser('family',{registrant:false,registerUntil:Date.now()+60000}),secret),'family@example.test');
});

test('pause invalidates recipient snapshots without a worker; old revision and old age fail closed', async t => {
  const f=await fixture(t);
  await f.request('sharing',{method:'PUT',body:{enabled:true}});
  const before=await f.state();
  const batch={revision:before.revision,views:[{email:'owner@example.test',view:{people:[{position:{lat:51,lon:0}}]}}]};
  assert.equal((await f.request('household/views',{token:household,method:'POST',body:batch})).status,200);
  assert.ok((await f.request('household/view',{token:f.tokens.owner})).body.view);
  await f.request('sharing',{method:'PUT',body:{enabled:false}});
  assert.equal((await f.request('household/view',{token:f.tokens.owner})).body.view,null);
  assert.equal((await f.request('household/views',{token:household,method:'POST',body:batch})).status,409);
  batch.revision=(await f.state()).revision;
  await f.request('household/views',{token:household,method:'POST',body:batch});
  f.db.exec("UPDATE household_views SET updated='2000-01-01T00:00:00.000Z'");
  assert.equal((await f.request('household/view',{token:f.tokens.owner})).body.view,null);
});

test('private steps and location consent do not opt into family health; minimal export obeys opt-out', async t => {
  const f=await fixture(t), start=new Date(Date.now()-60000).toISOString(), end=new Date().toISOString();
  const sync=await f.request('sync',{method:'POST',body:{health:[{id:'steps',kind:'steps',start,end,value:42,unit:'count',source:'Synthetic'}],locations:[],deleted:[]}});
  assert.equal(sync.status,200);
  const path=`household/steps?email=family%40example.test&from=${start}&to=${new Date(Date.now()+1000).toISOString()}`;
  assert.equal((await f.request(path,{token:household})).status,403);
  await f.request('sharing',{method:'PUT',body:{enabled:true}});
  assert.equal((await f.request(path,{token:household})).status,403);
  await f.request('steps-sharing',{method:'PUT',body:{enabled:true}});
  assert.deepEqual((await f.request(path,{token:household})).body,{steps:[{start,end,value:42}]});
  await f.request('steps-sharing',{method:'PUT',body:{enabled:false}});
  assert.equal((await f.request(path,{token:household})).status,403);
});

test('deletion survives downstream outage and duplicate requests; both acknowledgements are required', async t => {
  const f=await fixture(t), now=new Date().toISOString();
  await f.request('sync',{token:f.tokens.owner,method:'POST',body:{health:[{id:'hr',kind:'heart_rate',start:now,end:now,value:60,unit:'bpm',source:'Synthetic'}],locations:[],deleted:[]}});
  assert.equal((await f.request('data',{token:f.tokens.owner,method:'DELETE'})).status,202);
  const cookie=await f.browser('owner');
  assert.equal((await f.request('pair-code',{cookie,method:'POST',body:{}})).status,409);
  await f.request('data',{cookie,method:'DELETE'});
  const jobs=(await f.request('export/deletions',{token:healthToken})).body.jobs;
  assert.equal(jobs.length,1);
  const manifest=(await f.request(`export/deletions?id=${jobs[0].id}`,{token:healthToken})).body;
  assert.equal(manifest.tombstones[0].id,'hr');
  assert.equal(f.db.prepare('SELECT count(*) n FROM health').get().n,0);
  await f.request('household/deletions',{token:household,method:'POST',body:{id:jobs[0].id}});
  assert.equal((await f.request('pair-code',{cookie,method:'POST',body:{}})).status,409);
  await f.request('export/deletions',{token:healthToken,method:'POST',body:{id:jobs[0].id}});
  assert.equal((await f.request('pair-code',{cookie,method:'POST',body:{}})).status,200);
});

test('retention runs without another upload', async t => {
  const f=await fixture(t);
  f.db.prepare('INSERT INTO locations VALUES(?,?,?,?,?)').run('family','old','2000-01-01T00:00:00.000Z','{}','2000-01-01T00:00:00.000Z');
  pruneStore(f.db);
  assert.equal(f.db.prepare('SELECT count(*) n FROM locations').get().n,0);
});
