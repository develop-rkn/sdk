import AVFoundation
import SwiftUI
import UIKit
import Vision

struct MRZCaptureView: UIViewControllerRepresentable {
    let onMRZCaptured: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context _: Context) -> MRZCaptureViewController {
        MRZCaptureViewController(onMRZCaptured: onMRZCaptured, onCancel: onCancel)
    }

    func updateUIViewController(_: MRZCaptureViewController, context _: Context) {}
}

final class MRZCaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onMRZCaptured: (String) -> Void
    private let onCancel: () -> Void
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "faced.mrz.capture")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastAnalysisTime = CACurrentMediaTime()
    private var bestMRZText: String?
    private var stableCandidates: [String: Int] = [:]
    private var didAutoSubmit = false

    private let titleLabel = UILabel()
    private let resultLabel = UILabel()
    private let instructionLabel = UILabel()
    private let candidateLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let scanLine = UIView()

    init(onMRZCaptured: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onMRZCaptured = onMRZCaptured
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanLineAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureUI() {
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        let guide = UIView()
        guide.translatesAutoresizingMaskIntoConstraints = false
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
        guide.layer.borderWidth = 3
        guide.layer.cornerRadius = 22
        guide.backgroundColor = UIColor.black.withAlphaComponent(0.12)

        scanLine.translatesAutoresizingMaskIntoConstraints = false
        scanLine.backgroundColor = .systemGreen
        scanLine.layer.cornerRadius = 2
        scanLine.layer.shadowColor = UIColor.systemGreen.cgColor
        scanLine.layer.shadowOpacity = 0.9
        scanLine.layer.shadowRadius = 12
        scanLine.layer.shadowOffset = .zero
        guide.addSubview(scanLine)

        let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.layer.cornerRadius = 18
        overlay.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.text = "Scan passport MRZ"

        resultLabel.font = .systemFont(ofSize: 18, weight: .bold)
        resultLabel.textColor = .systemYellow
        resultLabel.textAlignment = .center
        resultLabel.text = "Position passport"

        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textColor = .secondaryLabel
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 3
        instructionLabel.text = "Place the two MRZ lines inside the passport frame. Avoid glare and keep the page flat."

        candidateLabel.font = .systemFont(ofSize: 15, weight: .bold)
        candidateLabel.textColor = .white
        candidateLabel.textAlignment = .center
        candidateLabel.numberOfLines = 1
        candidateLabel.text = "Reading..."
        candidateLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        candidateLabel.layer.cornerRadius = 14
        candidateLabel.clipsToBounds = true

        submitButton.setTitle("Use MRZ Manually", for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        submitButton.isEnabled = false
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, resultLabel, instructionLabel, candidateLabel, submitButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(guide)
        view.addSubview(overlay)
        view.addSubview(stack)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            guide.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            guide.bottomAnchor.constraint(equalTo: overlay.topAnchor, constant: -26),
            guide.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.18),

            scanLine.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 18),
            scanLine.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -18),
            scanLine.heightAnchor.constraint(equalToConstant: 4),
            scanLine.centerYAnchor.constraint(equalTo: guide.centerYAnchor),

            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),

            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18)
        ])
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureCaptureSession() : self?.showUnavailable("Camera permission is required.")
                }
            }
        default:
            showUnavailable("Camera permission is required.")
        }
    }

    private func configureCaptureSession() {
        do {
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                showUnavailable("Back camera is unavailable.")
                session.commitConfiguration()
                return
            }

            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            captureQueue.async { [weak self] in
                self?.session.startRunning()
            }
        } catch {
            showUnavailable("Could not start camera: \(error.localizedDescription)")
        }
    }

    private func showUnavailable(_ message: String) {
        titleLabel.text = "MRZ scan unavailable"
        resultLabel.text = "Unavailable"
        resultLabel.textColor = .systemRed
        instructionLabel.text = message
        candidateLabel.text = ""
        submitButton.isEnabled = false
    }

    private func startScanLineAnimation() {
        scanLine.layer.removeAnimation(forKey: "scan")
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = -40
        animation.toValue = 40
        animation.duration = 1.3
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLine.layer.add(animation, forKey: "scan")
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        guard !didAutoSubmit, now - lastAnalysisTime > 0.28 else { return }
        lastAnalysisTime = now

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            self?.handleTextResult(request)
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        request.regionOfInterest = CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.42)

        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([request])
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.instructionLabel.text = "Hold the passport steady and keep the MRZ in the green box."
            }
        }
    }

    private func handleTextResult(_ request: VNRequest) {
        guard !didAutoSubmit,
              let observations = request.results as? [VNRecognizedTextObservation] else { return }
        let texts = observations.compactMap { $0.topCandidates(1).first?.string }
        guard let lines = extractMRZLines(from: texts.joined(separator: "\n")) else {
            let guidance = guidanceMessage(for: observations, texts: texts)
            DispatchQueue.main.async { [weak self] in
                self?.candidateLabel.text = "Reading..."
                self?.resultLabel.text = guidance.title
                self?.resultLabel.textColor = guidance.color
                self?.instructionLabel.text = guidance.message
                self?.submitButton.isEnabled = false
            }
            return
        }

        let mrzText = lines.joined(separator: "\n")
        bestMRZText = mrzText
        let stableCount = incrementStableCount(for: mrzText)

        DispatchQueue.main.async { [weak self] in
            self?.candidateLabel.text = stableCount >= 2 ? "Confirmed" : "MRZ found"
            self?.resultLabel.text = stableCount >= 2 ? "MRZ stable" : "MRZ found"
            self?.resultLabel.textColor = stableCount >= 2 ? .systemGreen : .systemYellow
            self?.instructionLabel.text = stableCount >= 2
                ? "Reading confirmed. Validating check digits on the backend..."
                : "Hold steady for one more frame."
            self?.submitButton.isEnabled = true
        }

        if stableCount >= 2 {
            autoSubmit(mrzText)
        }
    }

    private func guidanceMessage(
        for observations: [VNRecognizedTextObservation],
        texts: [String]
    ) -> (title: String, message: String, color: UIColor) {
        let maxHeight = observations.map(\.boundingBox.height).max() ?? 0
        let hasText = texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if maxHeight < 0.025 {
            return ("Move closer", "Bring the phone closer until the MRZ letters are large and sharp.", .systemYellow)
        }

        if hasText {
            return ("Hold steady", "Keep the two MRZ lines inside the green box. Avoid glare and shadows.", .systemYellow)
        }

        return ("Find MRZ", "Aim at the bottom two lines of the passport data page.", .systemYellow)
    }

    private func incrementStableCount(for mrzText: String) -> Int {
        var nextCandidates: [String: Int] = [:]
        let count = (stableCandidates[mrzText] ?? 0) + 1
        nextCandidates[mrzText] = count
        stableCandidates = nextCandidates
        return count
    }

    private func autoSubmit(_ mrzText: String) {
        guard !didAutoSubmit else { return }
        didAutoSubmit = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            stopSession()
            onMRZCaptured(mrzText)
        }
    }

    private func extractMRZLines(from text: String) -> [String]? {
        let lines = text
            .uppercased()
            .split(whereSeparator: \.isNewline)
            .map { normalizeMRZLine(String($0)) }
            .filter { $0.count >= 30 }

        for index in 0..<(max(lines.count - 1, 0)) {
            let first = fitMRZLine(lines[index])
            let second = fitMRZLine(lines[index + 1])
            if let first, let second, first.hasPrefix("P") {
                return [first, second]
            }
        }

        let compact = normalizeMRZLine(text.uppercased())
        if let range = compact.range(of: "P<") {
            let start = compact.distance(from: compact.startIndex, to: range.lowerBound)
            if compact.count - start >= 88 {
                let firstStart = compact.index(compact.startIndex, offsetBy: start)
                let firstEnd = compact.index(firstStart, offsetBy: 44)
                let secondEnd = compact.index(firstEnd, offsetBy: 44)
                return [String(compact[firstStart..<firstEnd]), String(compact[firstEnd..<secondEnd])]
            }
        }

        return nil
    }

    private func normalizeMRZLine(_ line: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        return String(line.replacingOccurrences(of: "«", with: "<").filter { allowed.contains($0) })
    }

    private func fitMRZLine(_ line: String) -> String? {
        if line.count == 44 {
            return line
        }
        guard line.count > 44 else { return nil }
        if let range = line.range(of: "P<") {
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            if line.count - start >= 44 {
                let first = line.index(line.startIndex, offsetBy: start)
                let last = line.index(first, offsetBy: 44)
                return String(line[first..<last])
            }
        }
        return String(line.prefix(44))
    }

    @objc private func submitTapped() {
        guard let bestMRZText else { return }
        didAutoSubmit = true
        stopSession()
        onMRZCaptured(bestMRZText)
    }

    @objc private func cancelTapped() {
        stopSession()
        onCancel()
    }

    private func stopSession() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
