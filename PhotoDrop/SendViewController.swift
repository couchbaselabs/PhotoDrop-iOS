//
//  SendViewController
//  PhotoDrop
//
//  Created by Pasin Suriyentrakorn on 11/16/14.
//  Copyright (c) 2014 Couchbase. All rights reserved.
//

import UIKit
import AssetsLibrary
import AVFoundation

class SendViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    @IBOutlet weak var previewView: UIView!

    @IBOutlet weak var statusLabel: UILabel!
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var session: AVCaptureSession!
    var replicator: CBLReplication!

    var sharedAssets:[ALAsset]?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        if session == nil {
            startCaptureSession()
        }
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: - Action

    @IBAction func cancelAction(sender: AnyObject) {
        self.navigationController?.dismissViewControllerAnimated(true,
            completion: { () -> Void in
                if self.replicator != nil {
                    self.replicator.stop()
                    NSNotificationCenter.defaultCenter().removeObserver(self,
                        name: kCBLReplicationChangeNotification, object: self.replicator)
                    UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                }
        })
    }
    
    /*
    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: - Capture QR Code

    func startCaptureSession() {
        let app = UIApplication.sharedApplication().delegate as AppDelegate

        let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        if device == nil {
            app.showMessage("No video capture devices found", title: "")
            return
        }

        var error: NSError?
        let input = AVCaptureDeviceInput.deviceInputWithDevice(device, error: &error)
            as AVCaptureDeviceInput
        if error == nil {
            session = AVCaptureSession()
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            output.setMetadataObjectsDelegate(self, queue: dispatch_get_main_queue())
            session.addOutput(output)
            output.metadataObjectTypes = [AVMetadataObjectTypeQRCode]

            previewLayer = AVCaptureVideoPreviewLayer.layerWithSession(session)
                as AVCaptureVideoPreviewLayer
            previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
            previewLayer.frame = self.previewView.bounds
            self.previewView.layer.addSublayer(previewLayer)

            session.startRunning()
        } else {
            app.showMessage("Cannot start QRCode capture session", title: "Error")
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func captureOutput(captureOutput: AVCaptureOutput!,
        didOutputMetadataObjects metadataObjects: [AnyObject]!,
        fromConnection connection: AVCaptureConnection!) {
        if session == nil {
            // Workaround for iOS7 bugs
            return
        }

        for metadata in metadataObjects as [AVMetadataObject] {
            if metadata.type == AVMetadataObjectTypeQRCode {
                let transformed = previewLayer.transformedMetadataObjectForMetadataObject(metadata)
                    as AVMetadataMachineReadableCodeObject
                if let url = NSURL(string: transformed.stringValue) {
                    replicate(url)
                    session.stopRunning()
                    session = nil
                    break
                }
            }
        }
    }

    // MARK: - Replication

    func replicate(url: NSURL) {
        self.previewView.hidden = true;
        self.statusLabel.text = "Sending Photos ..."
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true

        let app = UIApplication.sharedApplication().delegate as AppDelegate
        var docIds: [String] = []
        for asset in sharedAssets! {
            let representation = asset.defaultRepresentation()
            var bufferSize = UInt(Int(representation.size()))
            var buffer = UnsafeMutablePointer<UInt8>(malloc(bufferSize))
            var buffered = representation.getBytes(buffer, fromOffset: 0,
                length: Int(representation.size()), error: nil)
            var data = NSData(bytesNoCopy: buffer, length: buffered, freeWhenDone: true)

            var error: NSError?
            let doc = app.database.createDocument()
            let rev = doc.newRevision()
            rev.setAttachmentNamed("photo", withContentType: "application/octet-stream", content: data)
            let saved = rev.save(&error)

            if saved != nil {
                docIds.append(doc.documentID)
            }
        }

        if docIds.count > 0 {
            replicator = app.database.createPushReplication(url)
            replicator.documentIDs = docIds

            NSNotificationCenter.defaultCenter().addObserverForName(kCBLReplicationChangeNotification,
                object: replicator, queue: nil) { (notification) -> Void in
                    if self.replicator.lastError == nil {
                        var totalCount = self.replicator.changesCount
                        var completedCount = self.replicator.completedChangesCount
                        if completedCount > 0 && completedCount == totalCount {
                            self.statusLabel.text = "Sending Completed"
                            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                        }
                    } else {
                        self.statusLabel.text = "Sending Abort"
                        UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                    }
            }
            replicator.start()
        }
    }

}