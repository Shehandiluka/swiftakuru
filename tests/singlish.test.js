// JS port of Shared/Singlish.swift (tables parsed from the Swift source) to test conversions.
const fs = require('fs');
const src = fs.readFileSync(__dirname + '/../Shared/Singlish.swift', 'utf8');
const sect = (name) => src.split(`static let ${name}`)[1].split(']\n')[0];
const vowels = {}, consonants = {}, specials = {};
for (const m of sect('vowels').matchAll(/"([^"]+)": \("([^"]*)", "([^"]*)"\)/g)) vowels[m[1]] = [m[2], m[3]];
for (const m of sect('consonants').matchAll(/"([^"]+)": "([^"]*)"/g)) consonants[m[1]] = m[2];
for (const m of sect('specials').matchAll(/"([^"]+)": "([^"]*)"/g)) specials[m[1]] = m[2];
const HAL = '්', ZWJ = '‍';
function match(s, i) {
  const max = Math.min(3, s.length - i);
  for (let len = max; len >= 1; len--) for (const ci of [false, true]) {
    let sub = s.slice(i, i + len).join(''); if (ci) sub = sub.toLowerCase();
    if (consonants[sub] !== undefined) return [{ t: 'c', c: consonants[sub] }, len];
    if (vowels[sub]) return [{ t: 'v', ind: vowels[sub][0], sign: vowels[sub][1] }, len];
    if (specials[sub]) return [{ t: 's', s: specials[sub] }, len];
  }
  return [{ t: 'o', o: s[i] }, 1];
}
function convert(r) {
  const s = [...r]; let out = '', i = 0;
  while (i < s.length) {
    const [tok, len] = match(s, i);
    if (tok.t === 'c') {
      const j = i + len;
      if (j < s.length) { const [n, nl] = match(s, j); if (n.t === 'v') { out += tok.c + n.sign; i = j + nl; continue; } }
      if (j < s.length && tok.c !== 'ර' && tok.c !== 'ය') { const [n, nl] = match(s, j); if (n.t === 'c' && (n.c === 'ර' || n.c === 'ය') && j + nl < s.length && match(s, j + nl)[0].t === 'v') { out += tok.c + HAL + ZWJ; i = j; continue; } }
      out += tok.c + HAL; i = j;
    } else if (tok.t === 'v') { out += tok.ind; i += len; } else if (tok.t === 's') { out += tok.s; i += len; } else { out += tok.o; i += len; }
  }
  return out;
}
const cases = {
  amma: 'අම්මා'.replace('ා', ''), // amma → අම්ම
  ammaa: 'අම්මා', thaaththaa: 'තාත්තා', thaththaa: 'තත්තා', lankaava: 'ලන්කාව', laxkaava: 'ලංකාව', shrii: 'ශ්‍රී', prashnaya: 'ප්‍රශ්නය', vidhyaava: 'විද්‍යාව',
  kohomadha: 'කොහොමද', mama: 'මම', oyaa: 'ඔයා', hodhayi: 'හොදයි', hozdhayi: 'හොඳයි', sthuthiyi: 'ස්තුතියි', aayuboovan: 'ආයුබෝවන්', aayubowan: 'ආයුබොවන්',
  geeya: 'ගේය', giiya: 'ගීය', kee: 'කේ', ee: 'ඒ', kii: 'කී', siKhaa: 'සිඛා', Ruthuva: 'ඍතුව', kRuthi: 'කෘති', paasala: 'පාසල', sinhala: 'සින්හල', sixhala: 'සිංහල', kaeema: 'කෑම'.replace('ෑ','ැ') + '', baeheyi: 'බැහෙයි',
  gedhara: 'ගෙදර', LamayaaTa: 'ළමයාඨ', lamayaata: 'ලමයාට', eyaa: 'එයා', Eka: 'ඒක', mokakdha: 'මොකක්ද', karanna: 'කරන්න', kaeevaadha: 'කෑවාද',
};
cases.kaeema = 'කෑම';
let fail = 0;
for (const [r, exp] of Object.entries(cases)) { const got = convert(r); const ok = got === exp; if (!ok) fail++; console.log(ok ? 'PASS' : 'FAIL', r.padEnd(14), got, ok ? '' : '(expected ' + exp + ')'); }
module.exports = { convert };
if (require.main !== module) return;
if (fail) { console.log(fail + ' failed'); process.exitCode = 1; }
