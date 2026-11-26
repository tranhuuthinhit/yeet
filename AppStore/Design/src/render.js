const { chromium } = require('playwright');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1440,height:900},deviceScaleFactor:2});
for (const f of process.argv.slice(2)){await p.goto('file://'+process.cwd()+'/'+f);await p.waitForTimeout(150);
await p.screenshot({path:f.replace('.html','.png')});}
await b.close();})();
