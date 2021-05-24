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
    var imageURl = "http://172.20.10.2:8080/4.PNG"
    
    //Переменные объектов
    var bicycleNode:SCNNode!
    var car1Node:SCNNode!
    var car2Node:SCNNode!
    var car3Node:SCNNode!
    var car4Node:SCNNode!
    var car5Node:SCNNode!
    
    //Количество машин в сцене
    let carsInScene = 5

    //Текущее количество машин в сцене
    var curNumOfCars = 0
    
    //Массив машин
    var cars: [SCNNode] = []

    //Аутлеты UI элементов
    @IBOutlet weak var sceneView: SCNView?
    @IBOutlet weak var newImageView: UIImageView?
    
    //Переменные для переключения между картинками
    var img = 0
    var imgIterator = 0
    
    
    //Функция, которая выполняется, когда приложение запускается
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Устанавливаем режим сглаживания (antialiasing)
        sceneView?.antialiasingMode = SCNAntialiasingMode.multisampling4X
        
        //Привязываем 3D сцену к UI элементу SCNView
        guard let myScene = SCNScene(named: "Main Scene.scn")
            else { fatalError("Unable to load scene file.") }
        sceneView?.scene = myScene
        
        //Привязываем объекты к их переменным
        bicycleNode = myScene.rootNode.childNode(withName: "Bicycle", recursively: true)
        car1Node    = myScene.rootNode.childNode(withName: "Car", recursively: true)
        car2Node    = myScene.rootNode.childNode(withName: "Car2", recursively: true)
        car3Node    = myScene.rootNode.childNode(withName: "Car3", recursively: true)
        car4Node    = myScene.rootNode.childNode(withName: "Car4", recursively: true)
        car5Node    = myScene.rootNode.childNode(withName: "Car5", recursively: true)
        
        //Заполняем массив переменных-машин
        cars.append(car1Node)
        cars.append(car2Node)
        cars.append(car3Node)
        cars.append(car4Node)
        cars.append(car5Node)
        
        //Итерируем по массиву машин
        for car in cars {
            //Изначально прячем машины
            car.isHidden = true
        }
        
        //Обращение к i-той машине
        //print("Global Coordinates: ", cars[4].simdWorldPosition as Any)
        
        
        
        //Выводим в консоль координаты машины
        //print(car1Node.simdWorldPosition)  //в глобальной СК
        //print(car1Node.position)           //в локальной СК
        
        //Прячем машину
        //car1Node.isHidden = true
        //Показываем машину
        //car1Node.isHidden = false
        
        
    }
 
    
    
    lazy var detectionRequest: VNCoreMLRequest = {
        do {
            //let model = try VNCoreMLModel(for: Road_Sign_Object_Detector_1().model) //модель со знаками
            let model = try VNCoreMLModel(for: CarsDetectorV1_1().model) //модель с машинами
            
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
        
        
        //Обновляем позицию машины
        //let newPosition = SCNVector3(x: 0, y: 0, z: cars[4].position.z + 1000/3)
        //cars[4].position = newPosition
        
        //Выводим в консоль координаты машины
        //print(car5Node.simdWorldPosition)  //в глобальной СК
        //print(car5Node.position)           //в локальной СК
        
        //Обновляем переменные для переключения изображения
        imgIterator = imgIterator+1
        img = imgIterator%4 //[0,3]
        
        switch img {
        case 0:
            imageURl = "http://172.20.10.2:8080/1.PNG"
        case 1:
            imageURl = "http://172.20.10.2:8080/2.PNG"
        case 2:
            imageURl = "http://172.20.10.2:8080/3.PNG"
        case 3:
            imageURl = "http://172.20.10.2:8080/4.PNG"
        default:
            imageURl = "http://172.20.10.2:8080/4.PNG"
        }
        
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
                        self?.newImageView?.image = image
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
        guard let image = self.newImageView?.image else {
            return
        }
        
        let imageSize = image.size
        let scale: CGFloat = 1
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)

        image.draw(at: CGPoint.zero)
        
        //Число машин в кадре
        let numCars = detections.count
        print("Число машин в кадре: ", numCars)
        
        //Если в кадре машин (numCars) меньше, чем машин сейчас в сцене (curNumOfCars), то скрываем лишние машины
        if (numCars < curNumOfCars) {
            let carsToHide = curNumOfCars - numCars //сколько машин надо спрятать
            for index in 1...carsToHide {
                cars[curNumOfCars - index].isHidden = true
            }
        }
        
        //Запоминаем на будущее, сколько машин было в текущем изображении (чтобы потом скрыть лишние)
        curNumOfCars = numCars
        
        //Итератор для машин
        var i = 0
        
        
        //Цикл, итерирующий по распознанным объектам
        for detection in detections {
            
            print(detection.labels.map({"\($0.identifier) confidence: \($0.confidence)"}).joined(separator: "\n"))
            print("------------")
            
//            The coordinates are normalized to the dimensions of the processed image, with the origin at the image's lower-left corner.
            let boundingBox = detection.boundingBox
            let rectangle = CGRect(x: boundingBox.minX*image.size.width, y: (1-boundingBox.minY-boundingBox.height)*image.size.height, width: boundingBox.width*image.size.width, height: boundingBox.height*image.size.height)
            UIColor(red: 0, green: 0.423529, blue: 1, alpha: 0.4).setFill()
            UIRectFillUsingBlendMode(rectangle, CGBlendMode.normal)
            
            
            //Если на изображении больше чем 5 машин, то не рисуем то, чего нет
            if (i <= 4) {
                //Рассчитываем положение машины
                let realDistance = 1.8537/Float(boundingBox.height) //расстояние до машины в метрах
                let xPosition = -1.8*(Float(boundingBox.midX)-0.5)  //X-координата автомобиля в глобальной СК
                let zPosition = -6.55+0.17*realDistance             //Z-координата автомобиля в глобальной СК
                
                //Помещаем машину в нужное место
                cars[i].worldPosition.x = xPosition
                cars[i].worldPosition.z = zPosition
                
                //Показываем машину
                cars[i].isHidden = false
                
                //Инкремент итератора машин
                i = i+1
            }//end of if-statement
            
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        self.newImageView?.image = newImage
    }
    
    
    
}
