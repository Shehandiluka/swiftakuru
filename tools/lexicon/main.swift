import Foundation
// Reads words.tsv (word \t count), writes lex.tsv (skeleton \t word \t count) sorted by skeleton bytes.
let input = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var rows: [(String, String, String)] = []
for line in input.split(separator: "\n") {
    let p = line.split(separator: "\t")
    guard p.count == 2 else { continue }
    let w = String(p[0])
    let s = Singlish.sinhalaSkeleton(w)
    if !s.isEmpty { rows.append((s, w, String(p[1]))) }
}
rows.sort { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
let out = rows.map { "\($0.0)\t\($0.1)\t\($0.2)" }.joined(separator: "\n") + "\n"
try! out.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print("lex rows:", rows.count)
