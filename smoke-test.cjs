const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const listeners = new Map();
const frames = [];
let now = 0;
class Element {
  constructor(id = '') { this.id=id; this.hidden=false; this.textContent=''; this.innerHTML=''; this.attributes={}; this.handlers={}; this.classList={add(){},remove(){},toggle(){}}; this.children=[]; }
  addEventListener(type, fn) { (this.handlers[type] ||= []).push(fn); }
  setAttribute(name,value) { this.attributes[name]=value; }
  click() { for (const fn of this.handlers.click || []) fn({target:this}); }
  set innerHTML(value) {
    this._html=value;
    this.children=[...value.matchAll(/data-action="([^"]+)"/g)].map((m)=>{const e=new Element();e.dataset={action:m[1]};return e;});
  }
  get innerHTML() { return this._html || ''; }
  querySelectorAll() { return this.children; }
  querySelector(selector) { const action=selector.match(/data-action="([^"]+)"/)?.[1];return this.children.find(e=>e.dataset?.action===action)||null; }
}

const ids=['#game','#overlay','#overlayContent','#hud','#toast','#soundButton','#stageStatus','#sectorNumber','#score','#sideCores','#sideGoal','#lives','#pauseButton'];
const elements=Object.fromEntries(ids.map(id=>[id,new Element(id)]));
elements['#game'].getContext=()=>new Proxy({createLinearGradient:()=>({addColorStop(){}})},{get(target,key){return target[key]||(()=>{});},set(target,key,value){target[key]=value;return true;}});
const document={querySelector:s=>elements[s]||(elements[s]=new Element(s)),querySelectorAll:()=>Array.from({length:5},()=>new Element()),addEventListener:(type,fn)=>(listeners.set(`document:${type}`,fn))};
const window={addEventListener:(type,fn)=>(listeners.set(`window:${type}`,fn))};
const storage=new Map();
const context={document,window,localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},performance:{now:()=>now},requestAnimationFrame:fn=>frames.push(fn),Math,Number,String,Set,Map,Array,Math,Date,console};
vm.runInNewContext(fs.readFileSync('game.js','utf8'),context,{filename:'game.js'});

assert.match(elements['#overlayContent'].innerHTML,/НАЧАТЬ ПОЛЁТ/,'main menu is rendered');
elements['#overlayContent'].querySelector('[data-action="start"]').click();
assert.equal(elements['#hud'].hidden,false,'new game opens the gameplay HUD');
assert.equal(elements['#overlay'].hidden,true,'new game dismisses the menu');

listeners.get('window:keydown')({key:'d',repeat:false,preventDefault(){}});
for(let i=0;i<6;i++){now+=16;const batch=frames.splice(0);for(const frame of batch)frame(now);}
listeners.get('window:keyup')({key:'d'});
listeners.get('window:keydown')({key:'Escape',repeat:false,preventDefault(){}});
assert.match(elements['#overlayContent'].innerHTML,/ПРОДОЛЖИТЬ/,'Escape opens pause');
elements['#overlayContent'].querySelector('[data-action="resume"]').click();
assert.equal(elements['#overlay'].hidden,true,'resume returns to gameplay');

elements['#pauseButton'].click();
assert.match(elements['#overlayContent'].innerHTML,/НАЧАТЬ ЗАНОВО/,'pause menu offers restart');
elements['#overlayContent'].querySelector('[data-action="restart"]').click();
assert.equal(elements['#hud'].hidden,false,'restart begins a fresh game');
assert.equal(elements['#overlay'].hidden,true,'restart closes pause overlay');

elements['#soundButton'].click();
assert.equal(elements['#soundButton'].attributes['aria-label'],'Звук включён','sound control toggles its accessible state');
console.log('Smoke test passed: menu, start, movement frames, pause, resume, restart, sound toggle.');

