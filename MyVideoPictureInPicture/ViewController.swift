//
//  ViewController.swift
//  MyVideoPictureInPicture
//
//  Created by Kenta Matsue on 2025/04/07.
//

import UIKit
import PhotosUI
import AVKit

class ViewController: UIViewController {
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var videoLayerView: UIView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var pipButton: UIButton!
    
    private var playButtonVideoURL: URL?

    private var selection = [String: PHPickerResult]()
    private var selectedAssetIdentifiers = [String]()
    private var selectedAssetIdentifierIterator: IndexingIterator<[String]>?
    private var currentAssetIdentifier: String?
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var observation: NSKeyValueObservation?
    
    @IBAction func presentPickerForImagesAndVideos(_ sender: Any) {
        presentPicker(filter: .videos)
    }
    
    @IBAction func presentPickerForImagesIncludingLivePhotos(_ sender: Any) {
        presentPicker(filter: PHPickerFilter.images)
    }

    @IBAction func presentPickerForLivePhotosOnly(_ sender: Any) {
        presentPicker(filter: PHPickerFilter.livePhotos)
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
    
    /// - Tag: PresentPicker
    private func presentPicker(filter: PHPickerFilter?) {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        
        // Set the filter type according to the user’s selection.
        configuration.filter = filter
        // Set the mode to avoid transcoding, if possible, if your app supports arbitrary image/video encodings.
        configuration.preferredAssetRepresentationMode = .current
        // Set the selection behavior to respect the user’s selection order.
        configuration.selection = .ordered
        // Set the selection limit to enable multiselection.
        configuration.selectionLimit = 0
        // Set the preselected asset identifiers with the identifiers that the app tracks.
        configuration.preselectedAssetIdentifiers = selectedAssetIdentifiers
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        displayNext()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            switch status {
            default:
                break
            }
        }
    }
}

private extension ViewController {
    
    /// - Tag: LoadItemProvider
    func displayNext() {
        guard let assetIdentifier = selectedAssetIdentifierIterator?.next() else { return }
        currentAssetIdentifier = assetIdentifier
        
        let progress: Progress?
        let itemProvider = selection[assetIdentifier]!.itemProvider
        if itemProvider.canLoadObject(ofClass: PHLivePhoto.self) {
            progress = itemProvider.loadObject(ofClass: PHLivePhoto.self) { [weak self] livePhoto, error in
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: livePhoto, error: error)
                }
            }
        }
        else if itemProvider.canLoadObject(ofClass: UIImage.self) {
            progress = itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                DispatchQueue.main.async {
                    self?.handleCompletion(assetIdentifier: assetIdentifier, object: image, error: error)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
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
        } else {
            progress = nil
        }
        
        displayProgress(progress)
    }
    
    func handleCompletion(assetIdentifier: String, object: Any?, error: Error? = nil) {
        guard currentAssetIdentifier == assetIdentifier else { return }
        if let livePhoto = object as? PHLivePhoto {
            displayLivePhoto(livePhoto)
        } else if let image = object as? UIImage {
            displayImage(image)
        } else if let url = object as? URL {
            displayVideoPlayButton(forURL: url)
        } else if let error = error {
            print("Couldn't display \(assetIdentifier) with error: \(error)")
            displayErrorImage()
        } else {
            displayUnknownImage()
        }
    }
    
}

private extension ViewController {
    
    func displayEmptyImage() {
        displayImage(UIImage(systemName: "photo.on.rectangle.angled"))
    }
    
    func displayErrorImage() {
        displayImage(UIImage(systemName: "exclamationmark.circle"))
    }
    
    func displayUnknownImage() {
        displayImage(UIImage(systemName: "questionmark.circle"))
    }
    
    func displayProgress(_ progress: Progress?) {
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = progress
        progressView.isHidden = progress == nil
    }
    
    func displayVideoPlayButton(forURL videoURL: URL?) {
        playButtonVideoURL = videoURL
        playButton.isHidden = videoURL == nil
        progressView.observedProgress = nil
        progressView.isHidden = true
        if let videoURL {
            player = AVPlayer(url: videoURL)
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.frame = .init(origin: .zero, size: videoLayerView.frame.size)
            playerLayer?.videoGravity = .resizeAspect
            if let playerLayer = playerLayer {
                videoLayerView.layer.addSublayer(playerLayer)
            }
            setupPictureInPicture()
        }
    }
    
    func displayLivePhoto(_ livePhoto: PHLivePhoto?) {
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = nil
        progressView.isHidden = true
    }
    
    func displayImage(_ image: UIImage?) {
        playButtonVideoURL = nil
        playButton.isHidden = true
        progressView.observedProgress = nil
        progressView.isHidden = true
    }
    
    @IBAction func didTapPlayButton(_ sender: Any) {
        guard let player else {
            return
        }
        switch player.timeControlStatus {
        case .playing:
            player.pause()
            playButton.setImage(.init(systemName: "play.fill"), for: .normal)
        case .paused:
            player.play()
            playButton.setImage(.init(systemName: "pause.fill"), for: .normal)
        case .waitingToPlayAtSpecifiedRate:
            print("バッファリング中に変わりました")
        @unknown default:
            print("不明な状態に変わりました")
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
                // Update the PiP button's enabled state.
                self?.pipButton.isEnabled = change.newValue ?? false
            }
        } else {
            // PiP isn't supported by the current device. Disable the PiP button.
            pipButton.isEnabled = false
        }
    }
    
    @IBAction func togglePictureInPictureMode(_ sender: UIButton) {
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }
}

extension ViewController: PHPickerViewControllerDelegate {
    /// - Tag: ParsePickerResults
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
        
        if selection.isEmpty {
            displayEmptyImage()
        } else {
            displayNext()
        }
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
