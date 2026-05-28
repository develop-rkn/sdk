import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UIKit
import Vision

struct ActiveLivenessCaptureView: UIViewControllerRepresentable {
    let onCompleted: (UIImage, LivenessSubmission) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context _: Context) -> ActiveLivenessViewController {
        ActiveLivenessViewController(onCompleted: onCompleted, onCancel: onCancel)
    }

    func updateUIViewController(_: ActiveLivenessViewController, context _: Context) {}
}

enum LivenessChallenge: String, CaseIterable {
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    case blink = "blink"
    case finalSelfie = "final_selfie"

    var instruction: String {
        switch self {
        case .turnLeft:
            return "Turn your head left"
        case .turnRight:
            return "Turn your head right"
        case .blink:
            return "Blink once"
        case .finalSelfie:
            return "Center your face for the selfie"
        }
    }

    var defaultDetail: String {
        switch self {
        case .turnLeft:
            return "Slowly turn your head to the left."
        case .turnRight:
            return "Slowly turn your head to the right."
        case .blink:
            return "Look at the camera and blink naturally."
        case .finalSelfie:
            return "Look straight ahead and hold still — we'll take the selfie automatically."
        }
    }

    var holdSeconds: CFTimeInterval {
        switch self {
        case .blink:
            return 0
        case .turnLeft, .turnRight:
            return 0.7
        case .finalSelfie:
            return 0.6
        }
    }

    static func randomSequence() -> [LivenessChallenge] {
        [.turnLeft, .turnRight].shuffled() + [.blink, .finalSelfie]
    }
}

final class ActiveLivenessViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onCompleted: (UIImage, LivenessSubmission) -> Void
    private let onCancel: () -> Void
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "faced.active-liveness.capture")
    private let visionSequence = VNSequenceRequestHandler()
    private let ciContext = CIContext()
    private let challenges = LivenessChallenge.randomSequence()
    private let startedAt = Date()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentChallengeIndex = 0
    private var satisfiedFrames = 0
    private var analyzedFrames = 0
    private var lastAnalysisTime = CACurrentMediaTime()
    private var latestPixelBuffer: CVPixelBuffer?
    private var finalSelfiePixelBuffer: CVPixelBuffer?
    private var isCompleted = false
    private var isAdvancing = false
    private var satisfiedStartedAt: CFTimeInterval?
    private var hasSeenOpenEyes = false
    private var maxOpenEyeRatio: CGFloat = 0
    private var unsatisfiedFrameStreak = 0
    private let haptics = UINotificationFeedbackGenerator()

    private let instructionLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressLabel = UILabel()
    private let resultLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let faceGuideView = UIView()
    private let stepStack = UIStackView()
    private var stepDots: [UIView] = []

    init(
        onCompleted: @escaping (UIImage, LivenessSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCompleted = onCompleted
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
        haptics.prepare()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        faceGuideView.layer.cornerRadius = faceGuideView.bounds.width / 2
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

        faceGuideView.translatesAutoresizingMaskIntoConstraints = false
        faceGuideView.layer.borderWidth = 4
        faceGuideView.layer.borderColor = UIColor.systemYellow.cgColor
        faceGuideView.backgroundColor = .clear
        faceGuideView.layer.shadowColor = UIColor.systemYellow.cgColor
        faceGuideView.layer.shadowOpacity = 0.35
        faceGuideView.layer.shadowRadius = 18
        faceGuideView.layer.shadowOffset = .zero

        stepStack.axis = .horizontal
        stepStack.alignment = .center
        stepStack.distribution = .equalSpacing
        stepStack.spacing = 10
        stepStack.translatesAutoresizingMaskIntoConstraints = false
        stepDots = challenges.indices.map { _ in
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 5
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.35)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10)
            ])
            stepStack.addArrangedSubview(dot)
            return dot
        }

        let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.layer.cornerRadius = 28
        overlay.clipsToBounds = true

        instructionLabel.font = .systemFont(ofSize: 28, weight: .bold)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 1
        instructionLabel.adjustsFontSizeToFitWidth = true
        instructionLabel.minimumScaleFactor = 0.75

        detailLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        detailLabel.textColor = .white.withAlphaComponent(0.75)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 2
        detailLabel.text = challenges.first?.defaultDetail ?? "Move slowly and hold still when the ring turns green."

        progressLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        progressLabel.textColor = .white.withAlphaComponent(0.7)
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 1

        resultLabel.font = .systemFont(ofSize: 15, weight: .bold)
        resultLabel.textColor = .systemYellow
        resultLabel.textAlignment = .center
        resultLabel.text = "Get ready"

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        var cancelConfiguration = UIButton.Configuration.filled()
        cancelConfiguration.title = "Cancel"
        cancelConfiguration.baseForegroundColor = .white
        cancelConfiguration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        cancelConfiguration.cornerStyle = .capsule
        cancelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        cancelButton.configuration = cancelConfiguration
        cancelButton.tintColor = .white
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [resultLabel, instructionLabel, detailLabel, progressLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(faceGuideView)
        view.addSubview(stepStack)
        view.addSubview(overlay)
        view.addSubview(stack)
        view.addSubview(cancelButton)
        view.bringSubviewToFront(cancelButton)

        NSLayoutConstraint.activate([
            faceGuideView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            faceGuideView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            faceGuideView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.68),
            faceGuideView.heightAnchor.constraint(equalTo: faceGuideView.widthAnchor),

            stepStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
            stepStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),

            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        updateInstruction()
        updateStepDots()
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
            session.sessionPreset = .medium

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                showUnavailable("Front camera is unavailable.")
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

            if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
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
        instructionLabel.text = "Active liveness unavailable"
        detailLabel.text = message
        progressLabel.text = ""
    }

    @objc private func cancelTapped() {
        isCompleted = true
        stopSession()
        DispatchQueue.main.async { [onCancel] in
            onCancel()
        }
    }

    private func updateInstruction(metric: String? = nil) {
        guard let challenge = challenges[safe: currentChallengeIndex] else { return }
        resultLabel.text = "In progress"
        resultLabel.textColor = .systemYellow
        instructionLabel.text = challenge.instruction
        progressLabel.text = "Step \(currentChallengeIndex + 1) of \(challenges.count)"
        if let metric {
            detailLabel.text = metric
        }
        setGuideSatisfied(false)
        updateStepDots()
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard !isCompleted,
              !isAdvancing,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        latestPixelBuffer = pixelBuffer
        let now = CACurrentMediaTime()
        guard now - lastAnalysisTime > 0.22 else { return }
        lastAnalysisTime = now
        analyzedFrames += 1

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            self?.handleVisionResult(request)
        }

        do {
            try visionSequence.perform([request], on: pixelBuffer, orientation: .leftMirrored)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.detailLabel.text = "Keep your face visible to the camera."
            }
        }
    }

    private func handleVisionResult(_ request: VNRequest) {
        guard !isCompleted,
              !isAdvancing,
              let observations = request.results as? [VNFaceObservation],
              let face = observations.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            resetChallengeProgress("No face detected. Move closer and face the camera.")
            return
        }

        let challenge = challenges[currentChallengeIndex]
        let yaw = CGFloat(truncating: face.yaw ?? NSNumber(value: 0))
        let centerX = face.boundingBox.midX
        let width = face.boundingBox.width
        let eyeRatio = eyeOpenRatio(face)
        let isSatisfied: Bool
        let metric: String

        switch challenge {
        case .turnLeft:
            isSatisfied = yaw > 0.14
            metric = "Detected angle \(formatted(yaw)). Turn left slowly until the step turns green."
        case .turnRight:
            isSatisfied = yaw < -0.14
            metric = "Detected angle \(formatted(yaw)). Turn right slowly until the step turns green."
        case .blink:
            if eyeRatio > maxOpenEyeRatio {
                maxOpenEyeRatio = eyeRatio
            }
            let openEnough = maxOpenEyeRatio > 0.20
            let closedThreshold = max(0.12, maxOpenEyeRatio * 0.60)
            hasSeenOpenEyes = openEnough
            isSatisfied = openEnough && eyeRatio < closedThreshold
            metric = openEnough
                ? "Now blink — close your eyes briefly."
                : "Look at the camera so we can see your eyes."
        case .finalSelfie:
            let isCentered = abs(yaw) < 0.20
                && centerX > 0.20 && centerX < 0.80
                && width > 0.13
            isSatisfied = isCentered && face.confidence > 0.4
            if isSatisfied, let pixelBuffer = latestPixelBuffer {
                finalSelfiePixelBuffer = pixelBuffer
            }
            metric = isCentered
                ? "Hold still — capturing your selfie."
                : "Center your face inside the ring and look straight ahead."
        }

        if isSatisfied {
            satisfiedFrames += 1
            unsatisfiedFrameStreak = 0
            if satisfiedStartedAt == nil {
                satisfiedStartedAt = CACurrentMediaTime()
            }
        } else {
            unsatisfiedFrameStreak += 1
            if unsatisfiedFrameStreak >= 3 {
                satisfiedFrames = 0
                satisfiedStartedAt = nil
            }
        }

        let holdActive = satisfiedStartedAt != nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isAdvancing else { return }
            self.updateInstruction(metric: isSatisfied ? self.holdProgressText(defaultMessage: metric) : metric)
            self.setGuideSatisfied(isSatisfied || holdActive)
        }

        let holdTarget = challenges[safe: currentChallengeIndex]?.holdSeconds ?? 0
        if let satisfiedStartedAt,
           CACurrentMediaTime() - satisfiedStartedAt >= holdTarget {
            advanceChallenge()
        }
    }

    private func resetChallengeProgress(_ message: String) {
        satisfiedFrames = 0
        satisfiedStartedAt = nil
        unsatisfiedFrameStreak = 0
        DispatchQueue.main.async { [weak self] in
            self?.resultLabel.text = "Keep going"
            self?.resultLabel.textColor = .systemYellow
            self?.detailLabel.text = message
            self?.setGuideSatisfied(false)
        }
    }

    private func advanceChallenge() {
        guard !isAdvancing else { return }
        isAdvancing = true
        let passedIndex = currentChallengeIndex
        let passedChallenge = challenges[passedIndex]
        satisfiedFrames = 0
        satisfiedStartedAt = nil
        hasSeenOpenEyes = false
        maxOpenEyeRatio = 0
        unsatisfiedFrameStreak = 0

        if passedChallenge == .finalSelfie, finalSelfiePixelBuffer == nil {
            finalSelfiePixelBuffer = latestPixelBuffer
        }

        currentChallengeIndex += 1
        let isLast = currentChallengeIndex >= challenges.count

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            haptics.notificationOccurred(.success)
            haptics.prepare()
            resultLabel.textColor = .systemGreen
            if isLast {
                resultLabel.text = "Liveness complete"
                instructionLabel.text = "Saving selfie..."
                detailLabel.text = "Hold on while we save your image."
                progressLabel.text = "All \(self.challenges.count) steps complete"
            } else {
                resultLabel.text = "Step passed"
                detailLabel.text = "Good. Pause for the next check..."
                progressLabel.text = "Step \(passedIndex + 1) passed"
            }
            setGuideSatisfied(true)
            updateStepDots(passedThrough: passedIndex)
        }

        if isLast {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishLiveness()
            }
        } else {
            let nextChallenge = challenges[currentChallengeIndex]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.isAdvancing = false
                self?.updateInstruction(metric: nextChallenge.defaultDetail)
            }
        }
    }

    private func finishLiveness() {
        guard !isCompleted else { return }
        isCompleted = true
        isAdvancing = false

        guard let pixelBuffer = finalSelfiePixelBuffer ?? latestPixelBuffer,
              let image = makeImage(from: pixelBuffer) else {
            isCompleted = false
            isAdvancing = false
            updateInstruction(metric: "Could not capture the final selfie frame. Please try the last check again.")
            return
        }

        stopSession()

        let submission = LivenessSubmission(
            decision: "passed",
            challenges: challenges.map(\.rawValue),
            frameCount: analyzedFrames,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            completedAt: ISO8601DateFormatter().string(from: Date())
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.onCompleted(image, submission)
        }
    }

    private func stopSession() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func makeImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.rightMirrored)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func eyeOpenRatio(_ face: VNFaceObservation) -> CGFloat {
        guard let leftEye = face.landmarks?.leftEye,
              let rightEye = face.landmarks?.rightEye else {
            return 1
        }

        let left = opennessRatio(points: leftEye.normalizedPoints)
        let right = opennessRatio(points: rightEye.normalizedPoints)
        return min(left, right)
    }

    private func opennessRatio(points: [CGPoint]) -> CGFloat {
        guard points.count >= 4 else { return 1 }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = max((xs.max() ?? 0) - (xs.min() ?? 0), 0.001)
        let height = max((ys.max() ?? 0) - (ys.min() ?? 0), 0)
        return height / width
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private func holdProgressText(defaultMessage: String) -> String {
        guard let target = challenges[safe: currentChallengeIndex]?.holdSeconds, target > 0 else {
            return defaultMessage
        }
        guard let satisfiedStartedAt else {
            return "\(defaultMessage) Hold steady..."
        }

        let elapsed = min(CACurrentMediaTime() - satisfiedStartedAt, target)
        let remaining = max(target - elapsed, 0)
        return "Good. Keep holding for \(String(format: "%.1f", remaining))s."
    }

    private func setGuideSatisfied(_ isSatisfied: Bool) {
        let color = isSatisfied ? UIColor.systemGreen : UIColor.systemYellow
        faceGuideView.layer.borderColor = color.cgColor
        faceGuideView.layer.shadowColor = color.cgColor
        faceGuideView.layer.shadowOpacity = isSatisfied ? 0.65 : 0.35
    }

    private func updateStepDots(passedThrough index: Int? = nil) {
        let passedIndex = index ?? (currentChallengeIndex - 1)
        for (offset, dot) in stepDots.enumerated() {
            if offset <= passedIndex {
                dot.backgroundColor = .systemGreen
            } else if offset == currentChallengeIndex {
                dot.backgroundColor = .systemYellow
            } else {
                dot.backgroundColor = UIColor.white.withAlphaComponent(0.35)
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
