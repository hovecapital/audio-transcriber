import AVFoundation
import Foundation

protocol AudioBufferDelegate: AnyObject {
    func audioRecorder(
        didReceiveBuffer buffer: AVAudioPCMBuffer,
        speaker: TranscriptSegment.Speaker
    )
}
