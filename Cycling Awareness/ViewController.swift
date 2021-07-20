//
//  ViewController.swift
//  Cycling Awareness
//
//  Created by Даниил Волошин on 5/23/21.
//

import UIKit
import CocoaAsyncSocket //File -> Swift Packages -> Import CocoaAsyncSocket
import SceneKit
import CoreML
import Vision
import ImageIO

class ViewController: UIViewController, UINavigationControllerDelegate, GCDAsyncUdpSocketDelegate {
    
    //Аутлеты UI элементов
    @IBOutlet weak var sceneView: SCNView?
    @IBOutlet weak var newImageView: UIImageView?
    @IBOutlet weak var labelField2: UILabel?
    
    //Параметры UDP обмена
    var socket : GCDAsyncUdpSocket?
    let PORT : UInt16 = 14000           //порт UDP-сокета
    var IP = ""                         //адрес айфона (определяется в функции viewDidLoad())
    let bufferSize = 9216               //длина буфера (одного UDP-пакета)
    let headerSize = 5                  //длина заголовка, в котором хранится ожидаемое количество пакетов
    var imageData : Data? = "".data(using: .utf8)  //сюда будет записываться изображение (оно передаётся пакетами по bufferSize байт)
    var packetCounter = 0               //счётчик принятых пакетов
    var numOfPackets  = 0               //ожидаемое число пакетов
    var waitingForFirstPacket = true    //флаг того, что мы ждём пакет с заголовком
    var badFramesCounter = 0            //отладочная переменная
    var startTime = Date()              //отладочная переменная
    var frameCounter = 0                //отладочная переменная
    
    //Сокет на отправку
    var outSocket : OutSocket!
    
    //Период основного цикла, секунд
    let cycleLength = 1
    
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

    //Переменные для переключения между картинками
    var img = 0
    var imgIterator = 0
    
    
    
    //Функция, которая выполняется, когда приложение запускается
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //User defaults
        //Если приложение ещё ни разу не запускалось, то мы не знаем имя Wi-Fi и пароль от Raspberry
        //Соответственно, если knowsWIFI = 0 (а по умолчанию он 0), то мы узнаём (запрашиваем) у Raspberry адрес и пароль и сохраняем это в постоянную память
        let defaults = UserDefaults.standard
        let knowsWIFI = defaults.bool(forKey: "knowsWIFI")
        let raspberryName  = defaults.string(forKey: "raspberryName")
        let raspberryPassword = defaults.string(forKey: "raspberryPassword")
    
        //Если ещё не знаем имя Wi-Fi и пароль от Raspberry
        if !knowsWIFI {
            defaults.set(true, forKey: "knowsWIFI")
            defaults.set("RASPBERRY", forKey: "raspberryName")  //на самом деле тут будет обмен по Bluetooth
            defaults.set("RASPBERRY", forKey: "raspberryPassword") //на самом деле тут будет обмен по Bluetooth
        }else{
            print(raspberryName ?? "No name yet")
            print(raspberryPassword ?? "No password yet")
        }
        
        
        //Создаём таймер для цикла, в котором будем обрабатывать изображения
        //let timer = Timer.scheduledTimer(timeInterval: TimeInterval(cycleLength), target: self, selector: #selector(cycle), userInfo: nil, repeats: true)
        
        //Узнаём IP адрес айфона
        IP = getWiFiAddress()!
        print("IP: ", IP)
        
        //Создаём UDP-сокет на приём
        let socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do {
            try socket.bind(toPort: PORT)
            try socket.enableBroadcast(true)
            try socket.beginReceiving()
        } catch _ as NSError { print("Issue with setting up listener") }
        
        //Инициируем сокет на отправку
        outSocket = OutSocket()
        outSocket.setupConnection {}
        
        //Шлём по UDP IP адрес айфона
        outSocket.send(message: IP)
        
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
    }
 
    
    
    lazy var detectionRequest: VNCoreMLRequest = {
        do {
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
    
    
    
    //Функция, которая исполняется циклически по таймеру
    @objc func cycle() {
        
        //Тело цикла
        
    }//end of function cycle()
    
    
    
    //Функция, которая исполняется по нажатии на кнопку
    @IBAction func testPhoto(sender: UIButton) {
        print("PEPEGA")
        
        //Запускаем таймер для расчёта времени, которое уходит на обработку изображения
        let begin = clock()
        
        //Обновляем переменные для переключения изображения
        imgIterator = imgIterator+1
        
        let imageURl = "http://172.20.10.4:8080/Video/Frames-1/frame-" + String(imgIterator) + ".jpg"
        
        //Захватываем изображение по HTTP
        guard let url = URL(string: imageURl) else {return}
        
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
        
        //Выводим время, которое ушло на выполнение функции
        let diff = Double(clock() - begin) / Double(CLOCKS_PER_SEC)
        print("Elapsed time: ", diff, " seconds")
        
    }//end of function testPhoto()
    
    
    
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
        
    }//end of function updateDetections()
    
    
    
    private func processDetections(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                //print("Unable to detect anything.\n\(error!.localizedDescription)")
                return
            }
        
            let detections = results as! [VNRecognizedObjectObservation]
            self.drawDetectionsOnPreview(detections: detections)
        }
        
    }//end of function processDetections()
    
    
    
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
        
    }//end of function drawDetectionsOnPreview()
    
    
    
    //Функция приёма пакета
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        
        packetCounter += 1
        //print("packetCounter: ", packetCounter, ", data: ", data.count, "bytes")
        //labelField?.text = String(packetCounter) + " packets received"
        
        //Получили нулевой пакет, содержащий кол-во пакетов, в которых будет изображение
        if (packetCounter == 1)&&(waitingForFirstPacket == true)&&(data.count == headerSize) {
            let str = String(decoding: data, as: UTF8.self)
            numOfPackets = Int(str)!
            waitingForFirstPacket = false
            //print(numOfPackets)
            return;
        }
        
        //Получили последний пакет
        if (packetCounter == numOfPackets + 1) {
            imageData!.append(data)
            packetCounter = 0
            waitingForFirstPacket = true
            showImage()
            /*
            //Создаём изображение
            if let image = UIImage(data: imageData!) {
                //Вызываем функию обработки полученного изображения
                self.updateDetections(for: image)
                DispatchQueue.main.async {
                    //Вызываем функцию, которая выводит изображение на экран
                    self.newImageView?.image = image
                }
            }
            
            //Выводим FPS
            let currentTime = Date()
            frameCounter += 1
            let averageFPS = Double(frameCounter)/(DateInterval(start: startTime, end: currentTime).duration)
            labelField2?.text = "Average FPS: " + String(averageFPS)
            */
 
            return;
        }

        //Получили пакет, который и не первый, и не последний
        //Если пакет битый (меньше bufferSize байт), то обнуляем буфер и ждём снова первого пакета
        if (data.count == bufferSize) {
            imageData!.append(data)
        }else{
            badFramesCounter += 1
            print("Битый кадр!")
            //print("badFramesCounter: ", badFramesCounter)
            //labelField?.text = "badFramesCounter: " + String(badFramesCounter)
            //Очищаем буфер для изображения
            imageData = "".data(using: .utf8)
            packetCounter = 0
            waitingForFirstPacket = true
        }
        
    }//end of function udpSocket()
    
    
    
    //Функция вывода изображения на экран
    func showImage() {
        
        //Выводим изображение на экран
        if let image = UIImage(data: imageData!) {
            /*
            //Вызываем функию обработки полученного изображения
            self.updateDetections(for: image)
            */
            DispatchQueue.main.async {
                self.newImageView?.image = image //асинхронно выводим изображение на экран
            }
        }
        
        //Очищаем буфер для изображения
        imageData = "".data(using: .utf8)
        
        
        //Выводим FPS
        let currentTime = Date()
        frameCounter += 1
        let averageFPS = Double(frameCounter)/(DateInterval(start: startTime, end: currentTime).duration)
        labelField2?.text = "Average FPS: " + String(averageFPS)
         
    }
    
 
    
    //Функция, которая возвращает IP адрес устройства (айфона)
    func getWiFiAddress() -> String? {
        var address : String?

        //Получаем список всех сетевых интерфейсорв устройства
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        //Цикл по каждому интерфейсу
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            //Проверяем, что это IPv4 интерфейс
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {

                //Проверяем имя интерфейса (нас интересует интерфейс под названием "bridge100")
                //en0 - интерфейс для подключения айфона к другим устройствам
                //bridge100 - интерфейс для подключения устройств к айфону в режиме модема
                let name = String(cString: interface.ifa_name)
                //print(name)
                if  name == "en0" {
                    //Конвертируем адрес интерфейса в человеческий вид
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    //print("Interface: ", name)
                    //print("Address: ", address!)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
    }
    
}



class OutSocket: NSObject, GCDAsyncUdpSocketDelegate {
    let IP = "192.168.4.1" //когда Raspberry в режиме точки доступа
    //let IP = "10.0.1.9" //когда Raspberry подключена к Wi-Fi
    let PORT:UInt16 = 5001
    var socket:GCDAsyncUdpSocket!
    override init(){
        super.init()
    }
    func setupConnection(success:(()->())){
        socket = GCDAsyncUdpSocket(delegate: self, delegateQueue:DispatchQueue.main)
          do { try socket.bind(toPort: PORT)} catch { print("")}
          do { try socket.connect(toHost:IP, onPort: PORT)} catch { print("joinMulticastGroup not proceed")}
          do { try socket.beginReceiving()} catch { print("beginReceiving not proceed")}
        success()
    }
    func send(message: String){
        let data = message.data(using: String.Encoding.utf8)!
        socket.send(data, withTimeout: 2, tag: 0)
    }
    //MARK:- GCDAsyncUdpSocketDelegate
    func udpSocket(_ sock: GCDAsyncUdpSocket, didConnectToAddress address: Data) {
        print("didConnectToAddress");
    }
    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotConnect error: Error?) {
        if let _error = error {
            print("didNotConnect \(_error )")
        }
    }
    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error?) {
          print("didNotSendDataWithTag")
    }
    func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        print("didSendDataWithTag")
    }
}
