import Foundation
import AVFoundation

extension AVAudioPCMBuffer {
    /// Буфер ScreenCaptureKit живёт только внутри
    /// колбэка - дальше память переиспользует система. Всё, что уходит на другую
    /// очередь, копируем.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let src = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard src.count == dst.count else { return nil }
        for i in 0..<src.count {
            guard let s = src[i].mData, let d = dst[i].mData else { continue }
            let bytes = Int(min(src[i].mDataByteSize, dst[i].mDataByteSize))
            memcpy(d, s, bytes)
            dst[i].mDataByteSize = UInt32(bytes)
        }
        return copy
    }

    /// Самый громкий сэмпл буфера по всем каналам, от 0 до 1.
    var peakLevel: Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        var peak: Float = 0
        let planes = format.isInterleaved ? 1 : Int(format.channelCount)
        let samples = Int(frameLength) * (format.isInterleaved ? Int(format.channelCount) : 1)
        for ch in 0..<planes {
            let p = data[ch]
            for i in 0..<samples {
                let v = abs(p[i])
                if v > peak { peak = v }
            }
        }
        return min(1, peak)
    }

}
