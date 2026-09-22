// Install Playwright in a separate tooling workspace and point PLAYWRIGHT_MODULE to its index.mjs.
import { mkdirSync } from 'node:fs';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
const origin = process.env.PREVIEW_ORIGIN ?? 'http://127.0.0.1:5295';
mkdirSync('artifacts', { recursive: true });
const browser = await chromium.launch({headless:true});
const errors=[];
for (const [name, viewport] of [['desktop',{width:1440,height:1100}],['phone',{width:390,height:844}]]) {
 const context=await browser.newContext({viewport}); const page=await context.newPage();
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(`${origin}/apple-app/`);
 await page.getByLabel('Email',{exact:true}).fill('alex@example.test');
 await page.getByRole('button',{name:'Continue',exact:true}).click();
 await page.getByText('Alex · only you').waitFor();
 await page.locator('.metric').first().waitFor();
 await page.screenshot({path:`artifacts/${name}-health.png`,fullPage:true});
 await page.getByRole('button',{name:'Family locations',exact:true}).click();
 await page.getByRole('heading',{name:'Sam',exact:true}).waitFor();
 if (await page.getByRole('heading',{name:'Robin',exact:true}).count()) throw new Error('Other family leaked');
 await page.screenshot({path:`artifacts/${name}-family.png`,fullPage:true});
 await page.getByRole('button',{name:'Movement',exact:true}).click();
 // The second chip is a WHOLE previous day; today's only has the walks that
 // have already happened, which makes the run depend on the clock.
 await page.locator('.day-strip .day').nth(1).click();
 await page.waitForFunction(()=>document.querySelectorAll('#movement-map path.trace').length>0);
 if(await page.locator('#movement-map line.trace-gap').count()===0) throw new Error(`${name} drew no gap between recording runs`);
 // The trace has to sit ON the basemap. Each tile carries the zoom level as its
 // z-index, so if the tile layer is `z-index:auto` it never becomes a stacking
 // context, those values escape into the frame, and 12 beats the overlay's 1 —
 // tiles paint over the track, the scale bar and the attribution.
 const layers = await page.evaluate(()=>Object.fromEntries(
   ['map-tiles','map-overlay','map-attrib'].map(c=>[c, getComputedStyle(document.querySelector('.'+c)).zIndex])));
 if(layers['map-tiles']==='auto') throw new Error(`${name} tile layer is not a stacking context`);
 if(!(Number(layers['map-tiles']) < Number(layers['map-overlay']))) throw new Error(`${name} basemap is not behind the track`);
 if(!(Number(layers['map-overlay']) < Number(layers['map-attrib']))) throw new Error(`${name} attribution is not on top`);
 if(await page.locator('.metric').count()<6) throw new Error(`${name} movement stats missing`);
 const timeline = page.locator('.timeline');
 await timeline.waitFor();
 // The mouse takes VIEWPORT coordinates and the timeline is below the fold, so
 // without this the move lands on nothing and the page never sees a pointer.
 await timeline.scrollIntoViewIfNeeded();
 const box = await timeline.boundingBox();
 const plot = await timeline.evaluate(el=>({left:+el.dataset.plotLeft,width:+el.dataset.plotWidth}));
 const atHour = hour => box.x + plot.left + plot.width*(hour/24);
 const midway = box.y + box.height/2;
 // 08:20 is inside the morning walk, so there is a fix to land the map's dot on.
 await page.mouse.move(atHour(8.33), midway);
 await page.waitForFunction(()=>document.querySelectorAll('#movement-map circle.trace-cursor').length>0);
 await page.waitForFunction(()=>/bpm/.test(document.getElementById('movement-readout').textContent));
 // 10:30 is between two recording runs, and a gap must refuse to place the dot.
 await page.mouse.move(atHour(10.5), midway);
 await page.waitForFunction(()=>document.querySelectorAll('#movement-map circle.trace-cursor').length===0);
 await page.waitForFunction(()=>/asleep|no location/.test(document.getElementById('movement-readout').textContent));
 await page.selectOption('#movement-colour','heart');
 await page.waitForFunction(()=>document.querySelectorAll('#movement-legend .legend-ramp i').length>0);
 await page.screenshot({path:`artifacts/${name}-movement.png`,fullPage:true});
 // The map has to actually be a map: drag it and the trace must move with it,
 // turn the wheel and the scale bar must disagree with itself.
 await page.locator('#movement-map').scrollIntoViewIfNeeded();
 const frame = await page.locator('#movement-map').boundingBox();
 const traced = await page.locator('#movement-map path.trace').first().getAttribute('d');
 await page.mouse.move(frame.x+frame.width/2, frame.y+frame.height/2);
 await page.mouse.down();
 await page.mouse.move(frame.x+frame.width/2+120, frame.y+frame.height/2+60);
 await page.mouse.up();
 await page.waitForFunction(d=>document.querySelector('#movement-map path.trace')?.getAttribute('d')!==d, traced);
 const scaled = await page.locator('.map-scale').innerText();
 await page.mouse.wheel(0,-500);
 await page.waitForFunction(v=>document.querySelector('.map-scale').innerText!==v, scaled);
 await page.getByRole('button',{name:'Connect & privacy',exact:true}).click();
 await page.getByRole('button',{name:'Create health & location QR code'}).click();
 await page.waitForFunction(()=>document.getElementById('pair-code').textContent.length>20);
 await page.getByLabel('Share my location with my family').uncheck();
 await page.getByRole('button',{name:'Family locations',exact:true}).click();
 await page.getByText('Location sharing is paused.',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Connect & privacy',exact:true}).click();
 await page.getByLabel('Share my location with my family').check();
 await page.waitForTimeout(250);
 if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)) throw new Error(`${name} overflow`);
 await page.getByRole('button',{name:'Sign out'}).click();
 await page.getByRole('heading',{name:'Sign in',exact:true}).waitFor();
 await context.close();
 console.log(`${name}: login, health, movement map, timeline scrub, family isolation, pairing, pause/resume, logout and layout passed`);
}
await browser.close();
if(errors.length)throw new Error(errors.join('\n'));
