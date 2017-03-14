//
//  Streamer.swift
//  Camera Streamer
//
//  Created by Cole Smith on 3/8/17.
//  Copyright © 2017 Cole Smith. All rights reserved.
//

import UIKit
import AVFoundation
import SwiftSocket

class Streamer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private let videoDispatchQueue = DispatchQueue(label: "video")
    private let captureSession = AVCaptureSession()
    private var client: TCPClient?
    private var backgroundThreadOn: Bool = false
    private var streamQueue: SyncQueue<String> = SyncQueue(sizeRestriction: 50)
    private var frameTimer: Timer?
    private var img: CGImage?
    
    deinit {
        captureSession.stopRunning()
    }
    
    // MARK: - Stream Control
    
    /**
     
     Starts all services.
     
     - Parameter serverURL: The URL to the TCP server
     - Parameter serverPort: The Port of the TCP server
     - Parameter streamingInterval: The frequnecy at which to push new frames to stream queue
     
     - Throws: `StreamerConnectionError`
     
     - Returns: `nil`
     
     */
    func start(serverURL: String, serverPort: Int, streamingInterval: Double) throws {
        do {
            
            // Start Camera
            startVideo()
            
            // Open TCP Connection
            try openTCPStream(url: serverURL, port: serverPort)
            
            // Start Stream
            streamVideo(interval: streamingInterval)
            
            // Start Transmission
            if let c = self.client {
                startAsyncStreamer(client: c)
            }
            
        } catch StreamerConnectionError.connectionTimedOut(let err){
            throw StreamerConnectionError.connectionTimedOut(err)
        }
    }
    
    /**
     
     Closes the TCP stream, stops streaming new frames to
     the stream queue, and stops the camera
     
     - Returns: `nil`
     
     */
    func stop() {
        // Stop the background thread
        backgroundThreadOn = false
        // End transmission
        if let c = self.client {
            c.close()
        }
        
        // Stop streaming frames
        if let t = self.frameTimer {
            t.invalidate()
        }
    }
    
    /**
     
     Initializes a TCP stream with a TCP server on the network.
     Will throw a `StreamerConnectionError` if connection fails
     
     - Parameter url:  The address at which the TCP server lives
     - Parameter port: The port at which the TCP server lives
     
     - Returns: `nil` or `StreamerConnectionError` with `String`
     
     */
    private func openTCPStream(url: String, port: Int) throws {
        let client = TCPClient(address: url, port: Int32(port))
        switch client.connect(timeout: 5) {
        case .success:
            // Connected
            self.client = client
            break
        case .failure(let error):
            throw StreamerConnectionError.connectionTimedOut(error.localizedDescription)
        }
    }
    
    /**
     
     Opens a new thread and constantly streams the information from a
     stream queue buffer.
     
     - Parameter client: Connected `TCPClient` Object
     
     - Returns: `nil`
     
     */
    private func startAsyncStreamer(client: TCPClient) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Background thread
            print("[ INF ] Starting Streamer background thread")
            self.backgroundThreadOn = true
            while self.backgroundThreadOn {
                while self.streamQueue.count != 0 {
                    // Send data while stream queue is not empty
                    if let first = self.streamQueue.first() {
                        switch client.send(string: first) {
                        case .success: usleep(10000)
                        case .failure(let error):
                            print("[ WRN ] Streamer encounted transmission error: " + error.localizedDescription)
                            self.stop()
                        }
                        
                        // Dequeue
                        self.streamQueue.removeAtIndex(index: 0)
                    }
                }
            }
            
            // The backgroundThreadOn evaluated to false,
            // close background stream
            print("[ INF ] Background thread closing")
            return
        }
    }
    
    // MARK: - AV Control
    
    /**
     
     Starts the camera
     
     - Returns: `nil`
     
     */
    private func startVideo() {
        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) {
            (granted: Bool) -> Void in
            guard granted else { return }
        }
        do {
            let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.videoDispatchQueue)
            self.captureSession.sessionPreset = AVCaptureSessionPresetMedium
            try self.captureSession.addInput(AVCaptureDeviceInput(device: device))
            self.captureSession.addOutput(output)
            self.captureSession.startRunning()
        } catch {
            print("[ ERR ] Video Capture Failed")
        }
    }
    
    /**
     
     Any data pushed to the stream buffer will be transmitted so long
     as the async streamer is active. Pushing to the stream buffer will
     never fail, while tranmission of data might.
     
     - Parameter data: The data to send to the server
     
     - Returns: `nil`
     
     */
    func pushToStreamBuffer(string: String) {
        streamQueue.append(newElement: string)
    }
    
    /**
     
     Will open a timer that constantly streams new frames to the stream queue
     in specified intervals
     
     - Parameter interval: The interval in seconds to push new frames to the queue
     
     - Returns: `nil`
     
     */
    private func streamVideo(interval: Double) {
        if let dat = self.img {
            self.frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { _ in
                let b64 = UIImagePNGRepresentation(UIImage(cgImage: dat))?.base64EncodedString().appending("\n")
                self.pushToStreamBuffer(string: b64!)
            })
        }
    }
    
    /**
     
     Converts the camera buffer into a CIImage. This allows for quick
     conversion to other formats like UIImage, Data, or PNG Data
     
     - Returns: `nil`
     
     */
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        self.videoDispatchQueue.async {
            // Get Pixel Buffer
            let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            
            // Lock base address
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

            let ciimage = CIImage(cvImageBuffer: pixelBuffer)
            let context = CIContext(options: nil)
            let cgimage = context.createCGImage(ciimage, from: CGRect(x: 0,
                                                                       y: 0,
                                                                       width: CVPixelBufferGetWidth(pixelBuffer),
                                                                       height: CVPixelBufferGetHeight(pixelBuffer)))
            self.img = cgimage
            
            // Unlock base address
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        }
    }
    
    // MARK: - Error Handling
    
    enum StreamerConnectionError: Error {
        case connectionTimedOut(String)
    }
}

// MARK: - Sync Queue

/**
 
 A thread-safe access queue wrapped around
 a Dispatch queue
 
 */
class SyncQueue<T> {
    
    private var queue: DispatchQueue
    private var array: [T]
    private var max: Int
    
    init(sizeRestriction: Int) {
        self.queue = DispatchQueue(label: "stream", attributes: .concurrent)
        self.array = []
        self.max = sizeRestriction
    }
    
    public func append(newElement: T) {
        if self.count <= self.max {
            self.queue.async(flags:.barrier) {
                self.array.append(newElement)
            }
        } else {
            print("[ WRN ] Pushed to full queue")
        }
    }
    
    public func removeAtIndex(index: Int) {
        self.queue.async(flags:.barrier) {
            self.array.remove(at: index)
        }
    }
    
    public var count: Int {
        var count = 0
        
        self.queue.sync {
            count = self.array.count
        }
        
        return count
    }
    
    public func first() -> T? {
        var element: T?
        
        self.queue.sync {
            if !self.array.isEmpty {
                element = self.array[0]
            }
        }
        
        return element
    }
}
