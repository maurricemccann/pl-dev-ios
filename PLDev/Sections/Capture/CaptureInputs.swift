import AVFoundation
import Speech
import SwiftUI
import UIKit

// The two things a phone adds to Intake's "Choose image or shoot": the camera, and the voice. Both stay out of sight until the
// app's Info.plist carries the usage line the system requires (the lines are in LANES-capture.md), so a build without them
// never asks for a permission it cannot explain.

/// "Shoot": the system camera, one picture back as JPEG.
struct CaptureCamera: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var available: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CaptureCamera
        init(_ parent: CaptureCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onImage(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// A voice note, written out on the phone as he speaks (on-device recognition where the phone has it). It becomes text in the box;
/// no recording is kept and nothing is synthesised.
final class CaptureDictation: @unchecked Sendable {
    static var available: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
            && SFSpeechRecognizer()?.isAvailable == true
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var running = false

    /// Starts listening. `onText` gets the whole transcript so far; `onEnd` fires once when listening stops for any reason.
    /// Returns a plain sentence when it could not start, nil when it is listening.
    func start(onText: @escaping @Sendable (String) -> Void, onEnd: @escaping @Sendable () -> Void) async -> String? {
        stop()
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return "Speech recognition is off for PL DEV in Settings." }
        guard await AVAudioApplication.requestRecordPermission() else { return "The microphone is off for PL DEV in Settings." }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return "Speech recognition is not available right now." }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try PLAudio.listening()
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return "This phone has no microphone to listen with." }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer) }
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            return "Listening would not start: \(plainSentence(error))"
        }
        running = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result { onText(result.bestTranscription.formattedString) }
            if error != nil || result?.isFinal == true {
                self?.stop()
                onEnd()
            }
        }
        return nil
    }

    func stop() {
        guard running || request != nil else { return }
        running = false
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
