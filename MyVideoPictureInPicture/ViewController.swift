
import UIKit
import PhotosUI
import AVKit
import GoogleMobileAds

class ViewController: UIViewController {
    @IBOutlet weak var videoLayerView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var navigationLabel: UILabel!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var pictureInPictureButton: UIButton!
    
    @IBOutlet weak var adBannerContainerView: UIView!
    
    
    private var playButtonVideoURL: URL?

    private var selection = [String: PHPickerResult]()
    private var selectedAssetIdentifiers = [String]()
    private var selectedAssetIdentifierIterator: IndexingIterator<[String]>?
    private var currentAssetIdentifier: String?
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var observation: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    
    @IBAction func presentPickerForImagesAndVideos(_ sender: Any) {
        presentPicker(filter: .videos)
    }
    
    private let _pipContent = VideoProvider()
    private var _pipController: AVPictureInPictureController?
    private let _bufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var _pipPossibleObservation: NSKeyValueObservation?
    private var _observer: NSObjectProtocol?
    private let _startButton = UIButton()
    
    var pipController: AVPictureInPictureController!
    var pipPossibleObservation: NSKeyValueObservation?
    var playerStatusObservation: NSKeyValueObservation?
    
    private func presentPicker(filter: PHPickerFilter?) {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        
        configuration.filter = filter
        configuration.preferredAssetRepresentationMode = .current
        configuration.selection = .ordered
        configuration.selectionLimit = 1
        configuration.preselectedAssetIdentifiers = selectedAssetIdentifiers
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.setToolbarHidden(false, animated: true)
        progressView.isHidden = true
        playButton.isEnabled = false
        setUpAdBanner()
    }
}

private extension ViewController {
    
    func handleCompletion(assetIdentifier: String, object: Any?, error: Error? = nil) {
        progressView.isHidden = true
        guard currentAssetIdentifier == assetIdentifier else { return }
        if let url = object as? URL {
            displayVideoPlayButton(forURL: url)
        }
    }
    
}

private extension ViewController {
    func displayVideoPlayButton(forURL videoURL: URL?) {
        playButtonVideoURL = videoURL
        playButton.isEnabled = videoURL != nil
        playButton.isHidden = videoURL == nil
        if let videoURL {
            playerLayer?.removeFromSuperlayer()
            player = AVPlayer(url: videoURL)
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.frame = .init(origin: .zero, size: videoLayerView.frame.size)
            playerLayer?.videoGravity = .resizeAspect
            if let playerLayer = playerLayer {
                videoLayerView.layer.addSublayer(playerLayer)
            }
            timeControlStatusObserver = player?.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, change in
                switch player.timeControlStatus {
                case .playing:
                    self?.playButton.isEnabled = true
                    self?.playButton.setImage(.init(systemName: "pause.fill"), for: .normal)
                case .paused:
                    self?.playButton.isEnabled = true
                    self?.playButton.setImage(.init(systemName: "play.fill"), for: .normal)
                case .waitingToPlayAtSpecifiedRate:
                    self?.playButton.isEnabled = false
                @unknown default:
                    break
                }
            }
            setupPictureInPicture()
        }
    }
    
    @IBAction func didTapPlayButton(_ sender: UIButton) {
        guard let player else {
            return
        }
        switch player.timeControlStatus {
        case .playing:
            player.pause()
        case .paused:
            player.play()
        default:
            break
        }
    }
    
    func setupPictureInPicture() {
        // Ensure PiP is supported by current device.
        if AVPictureInPictureController.isPictureInPictureSupported(), let playerLayer {
            // Create a new controller, passing the reference to the AVPlayerLayer.
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController.delegate = self


            pipPossibleObservation = pipController.observe(\AVPictureInPictureController.isPictureInPicturePossible,
    options: [.initial, .new]) { [weak self] _, change in
                guard let self else { return }
                let isEnabled = change.newValue ?? false
                pictureInPictureButton.isEnabled = isEnabled
                if isEnabled {
                    NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackgroundNotification(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
                } else {
                    NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActiveNotification(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
                }
            }
        } else {
            // PiP isn't supported by the current device. Disable the PiP button.
            pictureInPictureButton.isEnabled = false
        }
    }
    
    @IBAction func togglePictureInPictureMode(_ sender: UIButton) {
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }
    
    @objc func didEnterBackgroundNotification(_ notification: Notification?) {
        pipController.startPictureInPicture()
    }
    
    @objc func didBecomeActiveNotification(_ notification: Notification?) {
        pipController.stopPictureInPicture()
    }
}

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        let existingSelection = self.selection
        var newSelection = [String: PHPickerResult]()
        for result in results {
            let identifier = result.assetIdentifier!
            newSelection[identifier] = existingSelection[identifier] ?? result
        }
        
        // Track the selection in case the user deselects it later.
        selection = newSelection
        selectedAssetIdentifiers = results.map(\.assetIdentifier!)
        selectedAssetIdentifierIterator = selectedAssetIdentifiers.makeIterator()
        guard let assetIdentifier = selectedAssetIdentifierIterator?.next() else { return }
        currentAssetIdentifier = assetIdentifier
                
        let progress: Progress?
        let itemProvider = selection[assetIdentifier]!.itemProvider
        progress = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            do {
                guard let url = url, error == nil else {
                    throw error ?? NSError(domain: NSFileProviderErrorDomain, code: -1, userInfo: nil)
                }
                let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: localURL)
                try FileManager.default.copyItem(at: url, to: localURL)
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: localURL)
                }
            } catch let catchedError {
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: nil, error: catchedError)
                }
            }
        }
        progressView.isHidden = false
        progressView.observedProgress = progress
        navigationLabel.isHidden = true
    }
}

extension ViewController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("\(#function)")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("\(#function)")
        print("pip error: \(error)")
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        print("\(#function)")
    }
}

extension ViewController: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        print("\(#function)")
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        print("\(#function)")
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        print("\(#function)")
        return false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        print("\(#function)")
        print(newRenderSize)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        print("\(#function)")
        completionHandler()
    }
}

extension ViewController {
    private func setUpAdBanner() {
        // Initialize the BannerView.
        let bannerView = BannerView()

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        adBannerContainerView.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.leadingAnchor.constraint(equalTo: adBannerContainerView.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: adBannerContainerView.trailingAnchor),
            bannerView.topAnchor.constraint(equalTo: adBannerContainerView.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: adBannerContainerView.bottomAnchor)
        ])
        bannerView.adSize = currentOrientationAnchoredAdaptiveBanner(width: 375)
        bannerView.adUnitID = "ca-app-pub-4342629226243259/9360669677"
        bannerView.load(Request())
    }
}
