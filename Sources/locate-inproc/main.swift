import Foundation
import GaeaProtocol
import LocatePlugin
import MLXLocate
import MLXServeCore
import MLXToolKit

// The in-process reference for the plugin: one lane of Qwen3-VL locate loaded by MLXServeEngine in this process, with
// the lane configuration the worker uses (LocatePlugin) and the request it builds (`request`, `boxes(in:)`). It prints
// one JSON line: the boxes as the worker would return them, and the timings. Not part of the plugin bundle.
//
//   locate-inproc --image <png | jpeg> --prompt <text> [--count 1] [--lane int8 | int4] [--models-root <dir>]
//                 [--out <json>] [--runs 2]
//
// The picture is sent as it is: give it upright, as Gaea sends it to the worker.

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
func seconds(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

guard let imagePath = option("--image"), let prompt = option("--prompt") else {
    fail("usage: locate-inproc --image <png | jpeg> --prompt <text> [--count N] [--lane int8 | int4] [--models-root <dir>] [--out <json>] [--runs N]")
}
let count = Int(option("--count") ?? "") ?? 1
guard (1...maxBoxes).contains(count) else { fail("--count is 1–\(maxBoxes)") }
let quant = Quant(rawValue: option("--lane") ?? quants[0].rawValue) ?? quants[0]
guard let configuration = configuration(quant: quant) else { fail("no lane \(quant.rawValue); one of \(quants.map(\.rawValue))") }
let outPath = option("--out")
let runs = Int(option("--runs") ?? "") ?? 2
let modelsRoot = URL(fileURLWithPath: option("--models-root")
                     ?? NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models", isDirectory: true)

// The budget Gaea sends a worker on a large Mac (wiresWeights off, the automatic pool cap).
let engine = MLXServeEngine(workerBudget: WorkerBudget(ceilingBytes: 64_000_000_000, wiresWeights: false))
await engine.useModelStore(ModelStore(root: modelsRoot))
let id = PackageID(modelID)
_ = try await engine.register(LocatePackage.registration, configuration: configuration, id: id)

var clock = ContinuousClock.now
_ = try await engine.prepare(.imageAnalysis, package: id)
var result: [String: Any] = ["model": modelID, "lane": quant.rawValue, "count": count, "prepare_s": seconds(since: clock)]

let image = Image(format: imagePath.lowercased().hasSuffix(".png") ? .png : .jpeg, data: try Data(contentsOf: URL(fileURLWithPath: imagePath)))
var found: [JSONValue] = []
for run in 1...max(1, runs) {
    clock = ContinuousClock.now
    guard let response = try await engine.run(request(image: image, prompt: prompt, count: count), package: id) as? ImageAnalysisResponse else {
        fail("the model returned no answer")
    }
    result["run\(run)_s"] = seconds(since: clock)
    if run == 1 { found = try boxes(in: response.text) }
}
let boxesData = try JSONEncoder().encode(found)
result["boxes"] = try JSONSerialization.jsonObject(with: boxesData)
if let outPath { try boxesData.write(to: URL(fileURLWithPath: outPath)) }
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
