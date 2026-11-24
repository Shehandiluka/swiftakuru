// JS port of romanSkeleton / sinhalaSkeleton to check that typed Singlish finds dictionary words.
const fs = require('fs');
const src = fs.readFileSync(__dirname + '/../Shared/Singlish.swift', 'utf8');
const grab = (name) => Object.fromEntries([...src.split(`static let ${name}`)[1].split(']\n')[0].matchAll(/"([^"]+)": "([^"]*)"/g)].map(m => [m[1], m[2]]));
const sinhalaRoman = grab('sinhalaRoman'), signRoman = grab('signRoman');
function romanSkeleton(r) {
  r = r.toLowerCase();
  for (const [a, b] of [['zdh','nd'],['zd','nd'],['zg','ng'],['zb','mb'],['zj','nj'],['x','n'],['w','v'],['aee','a'],['aae','a'],['ae','a'],['ee','e'],['ii','i'],['oo','u'],['ea','e'],['ou','au'],['nd','d'],['ng','g'],['mb','b']]) r = r.split(a).join(b);
  let out = '', prev = ' ';
  const cs=[...r]; for (let i=0;i<cs.length;i++) { const ch=cs[i]; if (ch==='y' && 'aeiou'.includes(prev) && i+1<cs.length && 'aeiou'.includes(cs[i+1])) continue; if (ch === 'h' && 'kgcjtdpbs'.includes(prev)) continue; if (ch === prev) continue; out += ch; prev = ch; }
  return out;
}
function sinhalaSkeleton(si) {
  const s = [...si]; let roman = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i], cp = ch.codePointAt(0);
    if (sinhalaRoman[ch] !== undefined && cp >= 0x0D9A) { roman += sinhalaRoman[ch]; const n = s[i + 1]; if (!(n && (signRoman[n] !== undefined || n === '්'))) roman += 'a'; }
    else if (sinhalaRoman[ch] !== undefined) roman += sinhalaRoman[ch];
    else if (signRoman[ch] !== undefined) roman += signRoman[ch];
    else if (ch === 'ං') roman += 'n';
    else if (ch === '්' || ch === '‍' || ch === 'ඃ') {}
    else roman += ch;
  }
  return romanSkeleton(roman);
}
const words = fs.readFileSync(__dirname + '/../Shared/Resources/words_si.txt', 'utf8').split('\n').filter(Boolean);
const idx = words.map(w => [w, sinhalaSkeleton(w)]);
const tests = { kohomadha: 'කොහොමද', kohomada: 'කොහොමද', sthuthiyi: 'ස්තුතියි', stuthi: 'ස්තුතියි', hondayi: 'හොඳයි', hodai: 'හොඳයි', ayubowan: 'ආයුබෝවන්', thaththa: 'තාත්තා', amma: 'අම්මා', lankawa: 'ලංකාව', gedara: 'ගෙදර', yaaluwa: 'යාළුවා', karanna: 'කරන්න', puluwan: 'පුළුවන්', mokakda: 'මොකක්ද', adarei: 'ආදරෙයි', samawenna: 'සමාවෙන්න' };
let fail = 0;
for (const [r, exp] of Object.entries(tests)) {
  const sk = romanSkeleton(r);
  const hits = idx.filter(([w, s]) => s === sk || s.startsWith(sk)).map(x => x[0]);
  const ok = hits.includes(exp); if (!ok) fail++;
  console.log(ok ? 'PASS' : 'FAIL', r.padEnd(12), sk.padEnd(10), hits.slice(0, 5).join(' '), ok ? '' : '| want ' + exp + ' (' + sinhalaSkeleton(exp) + ')');
}
process.exitCode = fail ? 1 : 0;
