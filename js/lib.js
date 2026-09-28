const sb=supabase.createClient(SB_URL,SB_KEY);
const $=s=>document.querySelector(s),p2=n=>String(n).padStart(2,'0');
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rp=n=>'Rp'+Number(n).toLocaleString('id-ID');
const img=n=>sb.storage.from('images').getPublicUrl(n).data.publicUrl;
const tm=t=>{const[h,m]=t.split(':');return+h*60+ +m};
const fmt=m=>p2(Math.floor(m/60))+'.'+p2(m%60);
const ymd=d=>d.getFullYear()+'-'+p2(d.getMonth()+1)+'-'+p2(d.getDate());
const hm=t=>t.slice(0,5);
function freeSlots(bk,units){const f=Array(32).fill(false);for(const u of units)for(let i=0;i<32;i++){const a=360+i*30,b=a+30;if(!bk.some(x=>x.unit_id==u&&tm(x.start_time)<b&&tm(x.end_time)>a))f[i]=true}return f}
function freeRanges(f){const r=[];let s=null;for(let i=0;i<=32;i++){const ok=i<32&&f[i];if(ok&&s===null)s=i;if(!ok&&s!==null){r.push(fmt(360+s*30)+'–'+fmt(360+i*30));s=null}}return r}
function dayStatus(bk,units){const f=freeSlots(bk,units);let run=0,max=0;for(const x of f){run=x?run+1:0;max=Math.max(max,run)}return !units.length||max<4?'full':bk.length?'limited':'available'}
const DOT={available:'<span class="dot available"></span>Tersedia',limited:'<span class="dot limited"></span>Terbatas',full:'<span class="dot full"></span>Terbooking'};
