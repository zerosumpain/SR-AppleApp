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
 await page.getByLabel('Password',{exact:true}).fill('SR-local-demo-only!');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByText('Alex · only you').waitFor();
 await page.locator('.metric').first().waitFor();
 await page.screenshot({path:`artifacts/${name}-health.png`,fullPage:true});
 await page.getByRole('button',{name:'Family locations',exact:true}).click();
 await page.getByRole('heading',{name:'Sam',exact:true}).waitFor();
 if (await page.getByRole('heading',{name:'Robin',exact:true}).count()) throw new Error('Other family leaked');
 await page.screenshot({path:`artifacts/${name}-family.png`,fullPage:true});
 await page.getByRole('button',{name:'Connect & privacy',exact:true}).click();
 await page.getByRole('button',{name:'Create pairing code'}).click();
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
 console.log(`${name}: login, health, family isolation, pairing, pause/resume, logout and layout passed`);
}
await browser.close();
if(errors.length)throw new Error(errors.join('\n'));
