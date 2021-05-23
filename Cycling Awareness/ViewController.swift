//
//  ViewController.swift
//  Cycling Awareness
//
//  Created by Даниил Волошин on 5/23/21.
//

import UIKit
import SceneKit
import CoreML
import Vision
import ImageIO

class ViewController: UIViewController, UINavigationControllerDelegate {
    
    //Адрес изображения на локальном сервере
    let imageURl = "http://172.20.10.2:8080/picture.jpg"

    @IBOutlet weak var photoImageView: UIImageView?
    @IBOutlet weak var sceneView: SCNView?
    
    
    
    //Функция, которая выполняется, когда приложение запускается
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView?.antialiasingMode = SCNAntialiasingMode.multisampling2X
        guard let myScene = SCNScene(named: "Main Scene.scn")
            else { fatalError("Unable to load scene file.") }
        sceneView?.scene = myScene // Your app's SCNView
    }
 
    
    
    lazy var detectionRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: Road_Sign_Object_Detector_1().model)
            
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processDetections(for: request, error: error)
            })
            request.imageCropAndScaleOption = .scaleFit
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    
    //Функция, которая исполняется по нажатии на кнопку
    @IBAction func testPhoto(sender: UIButton) {
        print("PEPEGA")
        
        //Захватываем изображение по HTTP
        guard let url = URL(string: imageURl)else {
            return
        }
        DispatchQueue.global().async { [weak self] in
            if let data = try? Data(contentsOf: url) {
                if let image = UIImage(data: data) {
                    
                    //Вызываем функию обработки полученного изображения
                    self?.updateDetections(for: image)
                    DispatchQueue.main.async {
                        //Вызываем функцию, которая выводит изображение на экран
                        self?.photoImageView?.image = image
                    }
                }
            }
        }
        
    }
    
    private func updateDetections(for image: UIImage) {

        let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue))
        guard let ciImage = CIImage(image: image) else { fatalError("Unable to create \(CIImage.self) from \(image).") }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation!)
            do {
                try handler.perform([self.detectionRequest])
            } catch {
                print("Failed to perform detection.\n\(error.localizedDescription)")
            }
        }
    }
    
    private func processDetections(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                print("Unable to detect anything.\n\(error!.localizedDescription)")
                return
            }
        
            let detections = results as! [VNRecognizedObjectObservation]
            self.drawDetectionsOnPreview(detections: detections)
        }
    }
    
    func drawDetectionsOnPreview(detections: [VNRecognizedObjectObservation]) {
        guard let image = self.photoImageView?.image else {
            return
        }
        
        let imageSize = image.size
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)

        image.draw(at: CGPoint.zero)

        for detection in detections {
            
            print(detection.labels.map({"\($0.identifier) confidence: \($0.confidence)"}).joined(separator: "\n"))
            print("------------")
            
//            The coordinates are normalized to the dimensions of the processed image, with the origin at the image's lower-left corner.
            let boundingBox = detection.boundingBox
            let rectangle = CGRect(x: boundingBox.minX*image.size.width, y: (1-boundingBox.minY-boundingBox.height)*image.size.height, width: boundingBox.width*image.size.width, height: boundingBox.height*image.size.height)
            UIColor(red: 0, green: 0.423529, blue: 1, alpha: 0.4).setFill()
            UIRectFillUsingBlendMode(rectangle, CGBlendMode.normal)
            
            print("(", boundingBox.minX, ",", boundingBox.minY, ")")
            print("(", boundingBox.maxX, ",", boundingBox.maxY, ")")
            print(boundingBox.height)
            print(boundingBox.width)
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        self.photoImageView?.image = newImage
    }
    
    
    
}
