(() => {
  'use strict';
  const canvas = document.querySelector('#game');
  const ctx = canvas.getContext('2d');
  const overlay = document.querySelector('#overlay');
  const overlayContent = document.querySelector('#overlayContent');
  const hud = document.querySelector('#hud');
  const toast = document.querySelector('#toast');
  const W = 960, H = 600, GOAL = 6, TOTAL = 5;
  const keys = new Set();
  const game = { mode:'menu', sector:0, score:0, cores:0, lives:3, time:0, best:Number(localStorage.getItem('lumen-best') || 0), muted:true, shake:0, flash:0, last:0, toastTimer:0, objects:[], particles:[], walls:[], stars:[], player:null, portal:null };
  for(let i=0;i<110;i++) game.stars.push({x:Math.random()*W,y:Math.random()*H,r:Math.random()*1.5+.25,a:Math.random()*.65+.15,p:Math.random()*7});
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
  const setMode=m=>{game.mode=m; game.last=performance.now();};
  const soundButton=document.querySelector('#soundButton');
  let audio;
  function beep(freq=420,duration=.07,type='sine',volume=.045){if(game.muted)return;try{audio ||= new (window.AudioContext||window.webkitAudioContext)();if(audio.state==='suspended')audio.resume();const o=audio.createOscillator(),g=audio.createGain();o.type=type;o.frequency.value=freq;g.gain.setValueAtTime(volume,audio.currentTime);g.gain.exponentialRampToValueAtTime(.001,audio.currentTime+duration);o.connect(g);g.connect(audio.destination);o.start();o.stop(audio.currentTime+duration)}catch{}}
  function showToast(text){toast.textContent=text;toast.classList.add('show');game.toastTimer=1.7;}
  function overlayMarkup(kicker,title,copy,button,action,extra=''){
    overlay.hidden=false;overlayContent.innerHTML=`<div class="overlay-ornament">✳</div><div class="over-kicker">${kicker}</div><h1 class="over-title">${title}</h1><p class="over-copy">${copy}</p><button class="primary-button" data-action="${action}">${button}</button>${extra}`;
    overlayContent.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',()=>act(b.dataset.action)));
  }
  function menu(){setMode('menu');hud.hidden=true;document.querySelector('#stageStatus').textContent='ОЖИДАНИЕ ПИЛОТА';overlayMarkup('ПОСЛЕДНИЙ СИГНАЛ · 2189','Там, где<br>гаснут звёзды','Маяк замолчал. Пройди пять секторов, собери ядра света и верни сигнал домой. Только не дай тьме тебя коснуться.','НАЧАТЬ ПОЛЁТ','start',`<button class="secondary-button" data-action="how">УПРАВЛЕНИЕ И ЦЕЛЬ</button>${game.best?`<div class="over-kicker" style="margin-top:18px">ЛУЧШИЙ РЕЗУЛЬТАТ · ${String(game.best).padStart(4,'0')}</div>`:''}`);overlayContent.querySelector('[data-action="how"]')?.addEventListener('click',()=>overlayMarkup('ПРОТОКОЛ ПИЛОТА','Собирай.<br>Уклоняйся.','WASD или стрелки — движение. Пробел — рывок с короткой неуязвимостью. Собери 6 ядер в каждом секторе и доберись до портала. Esc — пауза.','ПОНЯТНО','menu'))}
  function act(action){if(action==='start'){newRun();return}if(action==='menu'){menu();return}if(action==='resume'){setMode('playing');overlay.hidden=true;hud.hidden=false;document.querySelector('#stageStatus').textContent='СИГНАЛ АКТИВЕН';return}if(action==='restart'){newRun();return}if(action==='next'){game.sector++;beginSector();return}}
  function newRun(){game.sector=0;game.score=0;game.lives=3;game.cores=0;game.time=0;game.particles=[];beginSector();}
  function beginSector(){
    game.cores=0;game.time=0;game.shake=0;game.flash=0;game.player={x:W/2,y:H/2,r:11,vx:0,vy:0,faceX:1,faceY:0,dash:0,dashCd:0,invuln:1.2};game.objects=[];game.walls=[];game.portal={x:W-76,y:H/2,r:27};
    const barrierCount=3+game.sector;
    for(let i=0;i<barrierCount;i++){
      const horizontal=Math.random()<.5, x=180+Math.random()*600,y=105+Math.random()*390,w=horizontal?100+Math.random()*100:13+Math.random()*7,h=horizontal?13+Math.random()*7:80+Math.random()*105;
      if(Math.hypot(x-W/2,y-H/2)<135||Math.hypot(x-game.portal.x,y-game.portal.y)<95)continue;
      game.walls.push({x,y,w,h});
    }
    for(let i=0;i<GOAL;i++){
      let p,tries=0;do{p={x:65+Math.random()*(W-130),y:75+Math.random()*(H-150),r:8};tries++}while(tries<80&&(distance(p,game.player)<100||distance(p,game.portal)<95||game.walls.some(w=>p.x>w.x-20&&p.x<w.x+w.w+20&&p.y>w.y-20&&p.y<w.y+w.h+20)||game.objects.some(o=>distance(p,o)<100)));
      game.objects.push({...p,type:'core',phase:Math.random()*7});
    }
    const enemyCount=Math.min(2+game.sector,6);
    for(let i=0;i<enemyCount;i++){
      let p,tries=0;do{p={x:55+Math.random()*(W-110),y:65+Math.random()*(H-130)};tries++}while(tries<80&&(distance(p,game.player)<190||game.walls.some(w=>p.x>w.x-30&&p.x<w.x+w.w+30&&p.y>w.y-30&&p.y<w.y+w.h+30)));
      game.objects.push({x:p.x,y:p.y,r:12,type:i%3===2?'wisp':'hunter',speed:31+game.sector*4+Math.random()*11,phase:Math.random()*6,turn:Math.random()<.5?-1:1});
    }
    setMode('playing');hud.hidden=false;overlay.hidden=true;document.querySelector('#sectorNumber').textContent=String(game.sector+1).padStart(2,'0');document.querySelector('#stageStatus').textContent='СИГНАЛ АКТИВЕН';updateHUD();
    if(game.sector>0){showToast(`СЕКТОР ${String(game.sector+1).padStart(2,'0')} · СИГНАЛ ОБНАРУЖЕН`);game.flash=.8;beep(560,.25,'triangle')}
  }
  function updateHUD(){document.querySelector('#score').textContent=String(game.score).padStart(4,'0');document.querySelector('#sideCores').innerHTML=`${String(game.cores).padStart(2,'0')} <i>/ ${GOAL}</i>`;document.querySelector('#sideGoal').textContent=game.cores>=GOAL?'ПОРТАЛ ОТКРЫТ':'СОБРАТЬ';document.querySelector('#lives').textContent='♥ '.repeat(game.lives).trim()||'—';document.querySelectorAll('.sector-node').forEach((n,i)=>{n.classList.toggle('active',i===game.sector);n.classList.toggle('done',i<game.sector)})}
  function circleRect(x,y,r,w){const cx=clamp(x,w.x,w.x+w.w),cy=clamp(y,w.y,w.y+w.h);return (x-cx)**2+(y-cy)**2<r*r}
  function moveCircle(obj,dx,dy){let nx=obj.x+dx; if(nx-obj.r<24||nx+obj.r>W-24||game.walls.some(w=>circleRect(nx,obj.y,obj.r,w)))nx=obj.x;obj.x=nx;let ny=obj.y+dy;if(ny-obj.r<24||ny+obj.r>H-24||game.walls.some(w=>circleRect(obj.x,ny,obj.r,w)))ny=obj.y;obj.y=ny;}
  function particles(x,y,color,count=10,speed=85){for(let i=0;i<count;i++){const a=Math.random()*Math.PI*2,s=Math.random()*speed;game.particles.push({x,y,vx:Math.cos(a)*s,vy:Math.sin(a)*s,life:.35+Math.random()*.55,max:.9,r:1+Math.random()*2,color})}}
  function hit(){const p=game.player;if(p.invuln>0)return;game.lives--;p.invuln=1.65;game.shake=.25;game.flash=.18;p.vx=-p.faceX*190;p.vy=-p.faceY*190;particles(p.x,p.y,'#ff988d',16,130);beep(135,.22,'sawtooth',.06);updateHUD();if(game.lives<=0){setMode('lost');document.querySelector('#stageStatus').textContent='СИГНАЛ ПОТЕРЯН';overlayMarkup('СВЯЗЬ ПРЕРВАНА','Тьма<br>победила.','Ты добрался до сектора '+String(game.sector+1).padStart(2,'0')+'. Собранные ядра всё равно оставили слабый след. Попробуй ещё раз.','ПОВТОРИТЬ ПОЛЁТ','restart',`<button class="secondary-button" data-action="menu">В ГЛАВНОЕ МЕНЮ</button>`);overlayContent.querySelector('[data-action="menu"]')?.addEventListener('click',menu)}}
  function complete(){if(game.sector<TOTAL-1){setMode('sectorDone');document.querySelector('#stageStatus').textContent='СЕКТОР ОЧИЩЕН';overlayMarkup(`СЕКТОР ${String(game.sector+1).padStart(2,'0')} · ОЧИЩЕН`,'Свет<br>возвращается.','Ядра стабилизированы. Впереди ещё один отрезок пути — маяк почти слышен.','СЛЕДУЮЩИЙ СЕКТОР','next',`<div class="over-kicker" style="margin-top:16px">ТЕКУЩИЙ СЧЁТ · ${String(game.score).padStart(4,'0')}</div>`);beep(760,.26,'sine')}else{setMode('won');document.querySelector('#stageStatus').textContent='МАЯК ЗАЖЖЁН';game.best=Math.max(game.best,game.score);try{localStorage.setItem('lumen-best',String(game.best))}catch{}overlayMarkup('МАЯК СНОВА СЛЫШЕН','Ты вернул<br>свет домой.','Пять секторов пройдены. Сигнал достиг дальних колоний — и кто-то ответил. Лучший результат: '+String(game.best).padStart(4,'0')+'.','ИГРАТЬ СНОВА','restart',`<button class="secondary-button" data-action="menu">В ГЛАВНОЕ МЕНЮ</button>`);overlayContent.querySelector('[data-action="menu"]')?.addEventListener('click',menu);beep(880,.45,'triangle')}}
  function step(dt){game.time+=dt;const p=game.player;if(!p)return;p.invuln=Math.max(0,p.invuln-dt);p.dashCd=Math.max(0,p.dashCd-dt);p.dash=Math.max(0,p.dash-dt);game.shake=Math.max(0,game.shake-dt);game.flash=Math.max(0,game.flash-dt);if(game.toastTimer>0&&(game.toastTimer-=dt)<=0)toast.classList.remove('show');
    let ix=(keys.has('d')||keys.has('arrowright')?1:0)-(keys.has('a')||keys.has('arrowleft')?1:0),iy=(keys.has('s')||keys.has('arrowdown')?1:0)-(keys.has('w')||keys.has('arrowup')?1:0),m=Math.hypot(ix,iy)||1;ix/=m;iy/=m;if(ix||iy){p.faceX=ix;p.faceY=iy}
    if(keys.has(' ')){keys.delete(' ');if(p.dashCd<=0&&(ix||iy)){p.dash=.18;p.dashCd=1.15;p.invuln=Math.max(p.invuln,.28);p.vx=ix*610;p.vy=iy*610;particles(p.x,p.y,'#8ce6d1',9,75);beep(610,.1,'triangle')}}
    if(p.dash>0){moveCircle(p,p.vx*dt,p.vy*dt)}else{const speed=190;p.vx+=(ix*speed-p.vx)*Math.min(1,dt*12);p.vy+=(iy*speed-p.vy)*Math.min(1,dt*12);moveCircle(p,p.vx*dt,p.vy*dt)}
    for(const o of game.objects){if(o.type==='core'){o.phase+=dt;if(distance(p,o)<p.r+o.r+4){o.type='gone';game.cores++;game.score+=100;particles(o.x,o.y,'#8ce6d1',14,100);beep(520+game.cores*35,.09,'sine');updateHUD();if(game.cores===GOAL){showToast('ВСЕ ЯДРА НАЙДЕНЫ · ПОРТАЛ АКТИВЕН');beep(820,.2,'triangle')}}}
      else if(o.type==='hunter'){const dx=p.x-o.x,dy=p.y-o.y,d=Math.hypot(dx,dy)||1;o.phase+=dt;const speed=o.speed*(d>240?1:.76);moveCircle(o,dx/d*speed*dt+Math.cos(o.phase*1.5)*9*dt,dy/d*speed*dt+Math.sin(o.phase*1.5)*9*dt);if(distance(p,o)<p.r+o.r)hit()}
      else if(o.type==='wisp'){o.phase+=dt;o.x+=Math.cos(o.phase*1.3)*o.speed*.38*dt;o.y+=Math.sin(o.phase*1.9)*o.speed*.38*dt;if(distance(p,o)<p.r+o.r)hit()}}
    game.objects=game.objects.filter(o=>o.type!=='gone');if(game.cores>=GOAL&&distance(p,game.portal)<p.r+game.portal.r){particles(game.portal.x,game.portal.y,'#b7ffe8',24,150);game.score+=250*(game.sector+1);updateHUD();complete()}
    for(const q of game.particles){q.x+=q.vx*dt;q.y+=q.vy*dt;q.vx*=Math.max(0,1-dt*2);q.vy*=Math.max(0,1-dt*2);q.life-=dt}game.particles=game.particles.filter(q=>q.life>0);
  }
  function draw(){ctx.save();if(game.shake>0)ctx.translate((Math.random()-.5)*game.shake*35,(Math.random()-.5)*game.shake*35);ctx.clearRect(0,0,W,H);const bg=ctx.createLinearGradient(0,0,W,H);bg.addColorStop(0,'#0b1b22');bg.addColorStop(.55,'#07131b');bg.addColorStop(1,'#0c1b22');ctx.fillStyle=bg;ctx.fillRect(0,0,W,H);
    for(const s of game.stars){ctx.globalAlpha=s.a*(.75+.25*Math.sin(game.time*1.3+s.p));ctx.fillStyle='#b2dacf';ctx.beginPath();ctx.arc(s.x,s.y,s.r,0,Math.PI*2);ctx.fill()}ctx.globalAlpha=1;
    ctx.strokeStyle='#17313a';ctx.lineWidth=1;ctx.setLineDash([2,8]);ctx.strokeRect(24,24,W-48,H-48);ctx.setLineDash([]);
    for(const w of game.walls){ctx.fillStyle='#10252b';ctx.fillRect(w.x,w.y,w.w,w.h);ctx.strokeStyle='#27434a';ctx.strokeRect(w.x+.5,w.y+.5,w.w-1,w.h-1);ctx.fillStyle='#8ce6d133';ctx.fillRect(w.x,w.y,Math.min(28,w.w),1)}
    if(game.portal){const active=game.cores>=GOAL;ctx.save();ctx.translate(game.portal.x,game.portal.y);ctx.rotate(game.time*.35);ctx.strokeStyle=active?'#8ce6d1':'#49646a';ctx.lineWidth=2;ctx.shadowBlur=active?20:7;ctx.shadowColor=active?'#8ce6d1':'#49646a';ctx.beginPath();ctx.arc(0,0,game.portal.r+Math.sin(game.time*2)*2,0,Math.PI*2);ctx.stroke();ctx.rotate(-game.time*.7);ctx.beginPath();ctx.arc(0,0,game.portal.r*.68,0,Math.PI*2);ctx.stroke();ctx.fillStyle=active?'#b6f5e56a':'#30454a88';ctx.beginPath();ctx.arc(0,0,9,0,Math.PI*2);ctx.fill();ctx.restore();ctx.shadowBlur=0;if(!active){ctx.fillStyle='#698287';ctx.font='9px "DM Mono",monospace';ctx.textAlign='center';ctx.fillText(`${game.cores}/${GOAL}`,game.portal.x,game.portal.y+4)}}
    for(const o of game.objects){if(o.type==='core'){const pulse=1+Math.sin(o.phase*3)*.14;ctx.save();ctx.translate(o.x,o.y);ctx.rotate(o.phase*.3);ctx.shadowBlur=18;ctx.shadowColor='#8ce6d1';ctx.fillStyle='#9ff1dc';ctx.beginPath();ctx.moveTo(0,-9*pulse);ctx.lineTo(7*pulse,0);ctx.lineTo(0,9*pulse);ctx.lineTo(-7*pulse,0);ctx.closePath();ctx.fill();ctx.restore()}else{ctx.save();ctx.translate(o.x,o.y);const wisp=o.type==='wisp';ctx.shadowBlur=15;ctx.shadowColor=wisp?'#c59af1':'#fa887d';ctx.fillStyle=wisp?'#c59af1':'#f49a89';ctx.beginPath();ctx.arc(0,0,o.r,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;ctx.fillStyle='#3b2230';ctx.beginPath();ctx.arc(-3,-1,1.5,0,Math.PI*2);ctx.arc(3,-1,1.5,0,Math.PI*2);ctx.fill();ctx.restore()}}
    for(const q of game.particles){ctx.globalAlpha=clamp(q.life/q.max,0,1);ctx.fillStyle=q.color;ctx.beginPath();ctx.arc(q.x,q.y,q.r,0,Math.PI*2);ctx.fill()}ctx.globalAlpha=1;
    const p=game.player;if(p){ctx.save();ctx.translate(p.x,p.y);ctx.rotate(Math.atan2(p.faceY,p.faceX));if(p.invuln>0&&Math.floor(game.time*16)%2===0)ctx.globalAlpha=.45;ctx.shadowBlur=21;ctx.shadowColor='#8ce6d1';ctx.fillStyle='#a4f0dc';ctx.beginPath();ctx.moveTo(15,0);ctx.lineTo(-9,-9);ctx.lineTo(-5,0);ctx.lineTo(-9,9);ctx.closePath();ctx.fill();ctx.shadowBlur=0;ctx.fillStyle='#e9fffa';ctx.beginPath();ctx.arc(1,0,3,0,Math.PI*2);ctx.fill();ctx.restore()}
    if(game.flash>0){ctx.globalAlpha=game.flash*1.4;ctx.fillStyle='#d2fff1';ctx.fillRect(0,0,W,H);ctx.globalAlpha=1}ctx.restore();requestAnimationFrame(draw)}
  function togglePause(){if(game.mode==='playing'){setMode('paused');overlay.hidden=false;document.querySelector('#stageStatus').textContent='ПОЛЁТ ПРИОСТАНОВЛЕН';overlayMarkup('ПАУЗА · СИГНАЛ СОХРАНЁН','Передышка.','Сектор '+String(game.sector+1).padStart(2,'0')+' · Ядра '+game.cores+'/'+GOAL+' · Счёт '+String(game.score).padStart(4,'0'),'ПРОДОЛЖИТЬ','resume',`<button class="secondary-button" data-action="restart">НАЧАТЬ ЗАНОВО</button><button class="secondary-button" data-action="menu">В ГЛАВНОЕ МЕНЮ</button>`)}else if(game.mode==='paused')act('resume')}
  window.addEventListener('keydown',e=>{const k=e.key.toLowerCase();if(['arrowup','arrowdown','arrowleft','arrowright',' '].includes(k))e.preventDefault();if(k==='escape'){togglePause();return}if(k===' '&&!e.repeat&&game.mode==='playing'){keys.add(' ');return}keys.add(k)});
  window.addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));window.addEventListener('blur',()=>{keys.clear();if(game.mode==='playing')togglePause()});document.addEventListener('visibilitychange',()=>{if(document.hidden&&game.mode==='playing')togglePause()});
  document.querySelector('#pauseButton').addEventListener('click',togglePause);soundButton.addEventListener('click',()=>{game.muted=!game.muted;soundButton.innerHTML=`${game.muted?'♫':'♪'} <span>ЗВУК ${game.muted?'ВЫКЛ':'ВКЛ'}</span>`;soundButton.setAttribute('aria-label',game.muted?'Звук выключён':'Звук включён');beep(650,.08)});
  let previous=performance.now();function loop(now){const dt=Math.min((now-previous)/1000,.04);previous=now;if(game.mode==='playing')step(dt);else if(game.toastTimer>0&&(game.toastTimer-=dt)<=0)toast.classList.remove('show');requestAnimationFrame(loop)}
  menu();requestAnimationFrame(draw);requestAnimationFrame(loop);
})();

