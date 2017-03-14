//
//  ViewController.swift
//  Camera Streamer
//
//  Created by Cole Smith on 3/8/17.
//  Copyright © 2017 Cole Smith. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    let connected = "✅"
    let disconnected = "⚪️"
    
    var streamer: Streamer?
    
    @IBOutlet weak var addressField: UITextField!
    @IBOutlet weak var portField: UITextField!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var connectionLabel: UILabel!
    @IBOutlet weak var errorsTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        errorsTextView.isHidden = true
        self.hideKeyboardWhenTappedAround()
    }
    
    @IBAction func connectButtonPressed(_ sender: AnyObject) {
        
        if streamer == nil {
            streamer = Streamer()
        }
        
        if let a = addressField.text, let pStr = portField.text, let p = Int(pStr) {
            do {
                try streamer?.start(serverURL: a, serverPort: p, streamingInterval: 0.1)
                // Connected
                connectionLabel.text = connected
                errorsTextView.isHidden = true
                print("[ INF ] Streamer open")
            } catch Streamer.StreamerConnectionError.connectionTimedOut(let err) {
                // Failed
                errorsTextView.text = String(err)
                errorsTextView.isHidden = false
                connectionLabel.text = disconnected
            } catch {
                // Unkown Fail
                connectionLabel.text = disconnected
            }
        }
    }
    
    @IBAction func disconnectButtonPressed(_ sender: AnyObject) {
        streamer?.stop()
        streamer = nil
        connectionLabel.text = disconnected
    }
}

extension UIViewController {
    func hideKeyboardWhenTappedAround() {
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(UIViewController.dismissKeyboard))
        view.addGestureRecognizer(tap)
    }
    
    func dismissKeyboard() {
        view.endEditing(true)
    }
}

