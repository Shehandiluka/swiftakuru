// Simulates the keyboard's replaceTail() against a fake text field whose deleteBackward removes
// one grapheme cluster (like UIKit), to make sure typing Singlish + space gives the right text.
const { convert } = require('./singlish.test.js');
const seg = new Intl.Segmenter('si', { granularity: 'grapheme' });
function field(mode) {
  let text = '';
  return {
    get ctx() { return mode === 'nocontext' ? null : text; },
    insert(s) { text += s; },
    del() { const g = [...seg.segment(text)]; if (g.length) text = text.slice(0, text.length - g[g.length - 1].segment.length); },
    get text() { return text; },
  };
}
function replaceTail(p, old, nw) {
  if (old === nw) return;
  const oldS = [...old], newS = [...nw];
  let common = 0; while (common < oldS.length && common < newS.length && oldS[common] === newS[common]) common++;
  const toRemove = oldS.length - common;
  const G = s => [...seg.segment(s)].length;
  if (toRemove > 0) {
    const before = [...(p.ctx ?? '')];
    if (before.length >= oldS.length && before.slice(-oldS.length).join('') === old) {
      const target = before.length - toRemove; let current = before.length, steps = 0;
      while (current > target && steps < toRemove + 3) { p.del(); steps++; const now = [...(p.ctx ?? '')].length; if (now >= current) break; current = now; }
      if (current <= target) { if (current < target) p.insert(before.slice(current, target).join('')); if (common < newS.length) p.insert(newS.slice(common).join('')); return; }
      for (let i = 0; i < G(old) - steps; i++) p.del(); p.insert(nw); return;
    }
    for (let i = 0; i < G(old); i++) p.del(); p.insert(nw); return;
  }
  if (common < newS.length) p.insert(newS.slice(common).join(''));
}
function type(p, words) {
  for (const w of words) { let roman = '', shown = ''; for (const ch of w) { roman += ch; const si = convert(roman); replaceTail(p, shown, si); shown = si; } p.insert(' '); }
  return p.text;
}
let fail = 0;
for (const mode of ['context', 'nocontext']) {
  const words = ['mama', 'kohomadha', 'prashnaya', 'shrii', 'vidhyaava', 'laxkaava', 'kRuthi', 'aayuboovan'];
  const got = type(field(mode), words);
  const exp = words.map(convert).join(' ') + ' ';
  const ok = got === exp; if (!ok) fail++;
  console.log(ok ? 'PASS' : 'FAIL', mode, got, ok ? '' : '| expected ' + exp);
}
// backspace inside a word: "kohomadha" then delete 3 roman letters
const p = field('context'); let roman = 'kohomadha', shown = convert(roman); p.insert(shown);
for (let i = 0; i < 3; i++) { roman = roman.slice(0, -1); const si = convert(roman); replaceTail(p, shown, si); shown = si; }
const ok = p.text === convert('kohoma'); if (!ok) fail++; console.log(ok ? 'PASS' : 'FAIL', 'backspace', p.text, convert('kohoma'));
process.exitCode = fail ? 1 : 0;
