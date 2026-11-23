# Swift Akuru — iOS සිංහල Keyboard

Helakuru වගේ Singlish → සිංහල keyboard එකක්, අමතර features එක්ක. (SwiftPayPOS (Private) Limited · swiftlk.com)

## Features
- **Singlish → සිංහල live** (type කරද්දිම සිංහලෙන් පෙන්නනවා). Helakuru වගේම රීති: `t=ට th=ත d=ඩ dh=ද x=ං zdh=ඳ`. `kr`/`ky` + ස්වරයක් ගැහුවම රකාරාංශය/යංශය (ක්‍ර, ක්‍ය) ඉබේම එනවා.
- **Smart suggestions**: වෙනත් spellings (ත/ට, ද/ඩ, න/ණ, ල/ළ…), වචන 330ක dictionary එකක්, typo වුණත් fuzzy match වෙනවා, ඔයා type කරන වචන ඉගෙනගන්නවා, ඊළඟට එන වචනයත් කියනවා.
- **English keyboard**: auto-correct (වැරදි correction එකක් නම් backspace එකෙන් undo), completions, auto-capital, space දෙපාරක් ඔබුවම full stop.
- **✨ Swift AI** (Gemini free key හෝ OpenAI): සිංහල ↔ English ↔ தமிழ் translate, grammar fix, formal / friendly කරන්න, කෙටි කරන්න, reply ideas 3ක්, Ask AI, emoji දාන්න.
- **Clipboard manager**: copy කරපු දේවල් 40ක් දක්වා මතක තියාගන්නවා, pin කරන්නත් පුළුවන්.
- **Emoji panel** + වචනයට ගැලපෙන emoji (adarei → ❤️, sthuthi → 🙏).
- **Long-press**: n → ණ ං ඤ ඞ ඳ … ; උඩ පේළියේ අංක.
- **Space bar එක ඇදලා** cursor එක move කරන්න පුළුවන්.
- **"අ" key එක**: සියලුම සිංහල අකුරු සහ පිලි (ZWJ ඇතුළුව) කෙලින්ම type කරන්න.
- **Themes 10ක්** (Swift Blue, Lanka Gold, AMOLED…), ඔයාගේම photo එක, keys ලොකු/පොඩි කරන්න, number row එක, key sound, vibration.
- **Text shortcuts**: `gm` → Good morning! ☀️, `@@` → email.
- Keyboard එක ඇතුළෙම **⚙️ Settings** තියෙනවා (app එක නැතුවත් වැඩ කරනවා).

## Build කරන්න (Mac එකක් ඕන නෑ)
iOS apps build කරන්න පුළුවන් macOS වල විතරයි. ඒ නිසා GitHub එකේ free cloud Mac එක පාවිච්චි කරනවා:

1. GitHub එකේ **අලුත් repository** එකක් හදන්න (උදා: `swiftakuru`). **Public** repo එකක නම් macOS build minutes free; private නම් මාසෙට build 10–15ක් විතර free.
2. මේ folder එකේ තියෙන **සියලුම files** (`.github` folder එකත් එක්ක) repo එකට upload කරන්න. GitHub Desktop පාවිච්චි කරන එක ලේසියි.
3. Repo එකේ **Actions** tab → **Build iOS** → **Run workflow**. විනාඩි 5–10කින් ඉවර වෙනවා.
4. ඉවර වුණාම run එක ඇතුළේ **Artifacts** යටතේ `SwiftAkuru-unsigned-ipa` download කරන්න → zip එක extract කරන්න → `SwiftAkuru-unsigned.ipa`.
   - Build එක fail වුණොත් `xcodebuild-log` artifact එක මට එවන්න. මම fix කරලා දෙන්නම්.

## iPhone එකට දාන්න (Windows PC + free Apple ID)
1. Windows එකට **iTunes** (apple.com එකෙන් ගන්න, Microsoft Store එකේ එක නෙවෙයි) සහ **Sideloadly** (sideloadly.io) install කරන්න.
2. iPhone එක USB එකෙන් connect කරලා "Trust" කියන්න.
3. Sideloadly එකට `.ipa` එක drag කරලා, ඔයාගේ Apple ID එක දාලා **Start** ඔබන්න.
4. iPhone එකේ: **Settings → General → VPN & Device Management** → ඔයාගේ Apple ID → **Trust**.
   iOS 16+ නම්: **Settings → Privacy & Security → Developer Mode → ON** (restart වෙනවා).
5. **Settings → General → Keyboard → Keyboards → Add New Keyboard → Swift Akuru**. ඊට පස්සේ ඒක ඔබලා **Allow Full Access ON** කරන්න.
6. ඕනෑම app එකක 🌐 key එක ඔබලා Swift Akuru තෝරන්න.

> Free Apple ID එකකින් දාපු app එක **දවස් 7කින් expire** වෙනවා. Sideloadly එකේ auto-refresh ON කරන්න, නැත්නම් සතියකට සැරයක් ආයේ දාන්න.
> Free install එකේ app එකයි keyboard එකයි අතරේ settings share වෙන්නේ නැහැ (App Group ඕන). ඒ නිසා keyboard එකේ **⚙️** එකෙන් settings වෙනස් කරන්න. AI key එක copy කරලා keyboard එකේ **✨ → Paste API key** ඔබන්න.

## AI key (free)
1. https://aistudio.google.com/apikey → **Create API key**.
2. Key එක copy කරන්න → keyboard එකේ ✨ AI → **📋 Paste API key from clipboard**.

## App Store එකට දාන්න
- Apple Developer Program එකට ($99/අවුරුද්දට) join වෙන්න.
- `project.yml` එකේ `DEVELOPMENT_TEAM` එකට ඔයාගේ Team ID එක දාන්න.
- Mac එකක් ලැබුණොත් Xcode වලින් Archive → Upload කරන්න. නැත්නම් Codemagic / GitHub Actions signing setup එකක් මම හදලා දෙන්නම්.
- Paid account එකක App Group වැඩ කරන නිසා app එකේ settings සහ photo theme keyboard එකටත් යනවා.

## iOS සීමාවන් (Apple නීති)
- Keyboard extensions වලට **microphone එක පාවිච්චි කරන්න බැහැ**, ඒ නිසා voice typing දාන්න බැහැ.
- **Password fields** වල සහ සමහර bank apps වල iOS එක ඉබේම Apple keyboard එක පෙන්නනවා.
- Clipboard, AI, sound/vibration වලට **Full Access** ඕන.

## Project structure
```
project.yml                 XcodeGen project (xcodegen generate)
.github/workflows/build.yml cloud build → unsigned IPA
App/                        SwiftUI app (setup, Singlish guide, AI, themes, shortcuts, learned words)
Keyboard/                   Keyboard extension (UIKit)
Shared/                     Singlish engine, suggestions, settings, AI client, themes, emoji, word list
tests/                      Transliteration tests (node tests/singlish.test.js)
```
