import Foundation
import GaeaPluginKit
import GaeaProtocol
import MLXLocate
import MLXToolKit

// gaea-plugin-locate: Qwen3-VL-4B-Instruct (Apache-2.0 weights and port) as a Gaea plugin on MES `image.locate`
// (Image §3.4, RFC 0010; Gaea AB-T-0483), on mlx-locate-swift through MLXServeEngine.
//
// One model, `qwen3-vl-locate`: a picture and a prompt in, boxes out, one box per instance the model finds, each with
// the prompt as its label and a score. Two lanes, the package's artifacts: int8 (the default) and int4.
//
// From 0.2.0 the boxes travel typed: the engine's `imageLocate` capability (contract 1.66.0, AB-A-0295), which
// mlx-locate-swift 0.3.0 serves. The worker sends `ImageLocateRequest` with the job's `count` and returns the answer's
// boxes as the `boxes` output's value. The package asks the model for every instance and answers with the best `count`
// by score, each box inside the picture. Gaea sends the picture upright, and MESKit clips, sorts and cuts the list
// again, which changes nothing in a list that already is. 0.1.x sent `imageAnalysis` and decoded JSON text.

public let modelID = "qwen3-vl-locate"
public let operation = "image.locate"

/// The most boxes one job returns: the offer's `limits.max_count`, and the package's own default cap.
public let maxBoxes = 16

/// The lanes, default first: the package's two artifacts.
public let quants: [Quant] = [.int8, .int4]

/// The package configuration for one lane, nil for a lane the model doesn't have; locate-inproc builds the same one.
/// An empty model directory lets the engine's store resolve the pinned artifact.
public func configuration(quant: Quant) -> LocateConfiguration? {
    quants.contains(quant) ? LocateConfiguration(quant: quant) : nil
}

/// The engine request for one job. The worker and locate-inproc both build it here, so the two send the same request.
public func request(image: Image, prompt: String, count: Int) -> ImageLocateRequest {
    ImageLocateRequest(image: image, prompt: prompt, count: count)
}

/// The answer's boxes as the `boxes` output's value: the list itself, each number a share of the upright picture. The
/// package gives every box a label and a score; a box without one carries none, never an invented value.
public func boxes(in response: ImageLocateResponse) -> [JSONValue] {
    response.boxes.map { box in
        var value: [String: JSONValue] = ["x": .double(box.x), "y": .double(box.y), "width": .double(box.width), "height": .double(box.height)]
        if let label = box.label { value["label"] = .string(label) }
        if let score = box.score { value["score"] = .double(score) }
        return .object(value)
    }
}

/// What a job asks for: the prompt and the count, checked.
struct Ask {
    var prompt: String
    var count: Int

    init(_ job: Job) throws {
        guard let text = try job.text("prompt")?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw GPPError(.invalidRequest, "image.locate needs a prompt: what to find.", detail: ["param": "prompt"])
        }
        prompt = text
        count = job.param("count")?.intValue ?? 1
        guard (1...maxBoxes).contains(count) else {
            throw GPPError(.invalidRequest, "count is 1–\(maxBoxes).", detail: ["param": "count"])
        }
    }
}

/// MES image.locate: one engine call, its boxes as the `boxes` value.
let locate = EngineOperation(operation) { job, session in
    let ask = try Ask(job)
    let response = try await session.run(request(image: try job.image("image"), prompt: ask.prompt, count: ask.count))
    guard let answer = response as? ImageLocateResponse else { throw GPPError(.internal, "The model returned no answer.") }
    return RunResult(outputs: [.value("boxes", .array(boxes(in: answer)))], effective: ["count": .int(Int64(ask.count))])
}

public func lanes() -> [LaneDefinition] {
    quants.map { LaneDefinition(id: $0.rawValue, default: $0 == quants[0], configuration: LocateConfiguration(quant: $0)) }
}

let offerModel: JSONValue = [
    "id": .string(modelID), "title": "Qwen3-VL locate",
    "license": ["spdx": "Apache-2.0", "commercial_use": true, "terms_url": "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct"],
    "memory_class": "medium", "speed_class": "fast", "quality_tiers": ["draft", "standard", "best"],
    "notes": .string("Finds what the prompt names and boxes it, one box for each instance (\"the character's hands\" gives two). "
        + "Write the prompt the way you want the box drawn: \"the character's face\" runs from the hairline to the chin. "
        + "An empty list means it isn't in the picture. The score ranks boxes; it isn't a calibrated probability. "
        + "Pictures are read at up to 1024 px on the long side, so small or crowded things may be missed."),
    "supports": ["seed": false],
    "limits": ["max_count": .int(Int64(maxBoxes))],
]

public let locatePlugin = GaeaPluginDefinition(
    id: "com.xocialize.gaea.locate",
    version: "0.2.0",
    minGaea: "1.10.0",
    team: "CFZS6RXUCP",
    repo: "https://github.com/xocialize-code/gaea-plugin-locate",
    title: "Locate",
    summary: "Where something is in a picture, as boxes: MES image.locate on Qwen3-VL-4B (Apache-2.0), one box for each "
        + "instance the prompt names, about half a second a picture.",
    license: "Apache-2.0",
    executable: "gaea-locate-worker",
    models: [
        .engine(LocatePackage.self, id: modelID, title: "Qwen3-VL locate", lanes: lanes(), operations: [locate]),
    ],
    offers: [
        PluginManifest.Offer(operation: operation, profile: "image", model: offerModel),
    ])
