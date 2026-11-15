import Foundation
@testable import GaeaPluginKit
import GaeaProtocol
@testable import LocatePlugin
import MLXLocate
import MLXToolKit
import Testing

@Suite struct LocatePluginTests {
    func job(_ params: [String: JSONValue], prompt: String? = "the fox") throws -> Job {
        var inputs: [String: [URL]] = [:]
        if let prompt {
            let url = FileManager.default.temporaryDirectory.appending(path: "locate-test-\(UUID().uuidString).txt")
            try Data(prompt.utf8).write(to: url)
            inputs["prompt"] = [url]
        }
        return Job(requestID: "r", job: "job_1", operation: "image.locate", model: modelID, lane: "int8", inputs: inputs,
                   params: params, modelParams: [:], adapters: [], seed: nil, outputDir: URL(fileURLWithPath: "/tmp"))
    }

    @Test func aJobNeedsAPromptAndACountInRange() throws {
        #expect(try Ask(job([:])).count == 1)
        #expect(try Ask(job(["count": 4])).count == 4)
        #expect(try Ask(job([:], prompt: "  the fox \n")).prompt == "the fox")
        #expect(throws: GPPError.self) { try Ask(job(["count": 0])) }
        #expect(throws: GPPError.self) { try Ask(job(["count": 17])) }
        #expect(throws: GPPError.self) { try Ask(job([:], prompt: "   ")) }
        #expect(throws: GPPError.self) { try Ask(job([:], prompt: nil)) }
    }

    @Test func theRequestIsThePackagesLocateModeWithTheCount() throws {
        let request = request(image: Image(format: .png, data: Data()), prompt: "the fox", count: 3)
        #expect(request.mode == .locate && request.prompt == "the fox")
        if case .int(let n)? = request.metaData["count"] { #expect(n == 3) } else { Issue.record("count isn't an int") }
    }

    @Test func theAnswersBoxesBecomeTheOutputValue() throws {
        let text = #"{"boxes":[{"x":0.25,"y":0.5,"width":0.125,"height":0.25,"label":"the fox","score":0.5}]}"#
        let boxes = try boxes(in: text)
        #expect(boxes.count == 1)
        #expect(boxes[0]["x"]?.doubleValue == 0.25 && boxes[0]["height"]?.doubleValue == 0.25)
        #expect(boxes[0]["label"]?.stringValue == "the fox" && boxes[0]["score"]?.doubleValue == 0.5)
        #expect(try LocatePlugin.boxes(in: #"{"boxes":[]}"#).isEmpty, "nothing found is an empty list, not an error")
        #expect(throws: GPPError.self) { try LocatePlugin.boxes(in: "I can't find it.") }
    }

    @Test func theManifestOffersOneModelOnImageLocateWithTwoLanes() throws {
        let manifest = try locatePlugin.manifest()
        #expect(manifest.version == "0.1.0" && manifest.minGaea == "1.9.0")
        #expect(manifest.models.map(\.id) == ["qwen3-vl-locate"])
        #expect(manifest.models[0].lanes.map(\.id) == ["int8", "int4"] && manifest.models[0].lanes[0].default)
        #expect(manifest.models[0].lanes.map { $0.resolved.weightSources.map(\.repo) }
            == [["mlx-community/Qwen3-VL-4B-Instruct-8bit"], ["mlx-community/Qwen3-VL-4B-Instruct-4bit"]])
        #expect(manifest.offers.map(\.operation) == ["image.locate"])
        let model = manifest.offers[0].model
        #expect(model["license"]?["spdx"] == "Apache-2.0" && model["named_only"] == nil)
        #expect(model["limits"]?["max_count"] == 16 && model["supports"]?["seed"] == false)
        #expect(manifest.engine?.contract == MLXEngineRelease.contract)
    }
}
