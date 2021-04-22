//: A UIKit based Playground for presenting user interface
  
import UIKit
import PlaygroundSupport

// Present the view controller in the Live View window
PlaygroundPage.current.liveView = MyViewController()
class MyViewController : UIViewController {
    let block = Block()
    let label = UILabel()
    let gradient = Gradient()
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .white

        block.backgroundColor = UIColor.clear
        block.frame = CGRect(x: 135, y: 150, width: 120, height: 120)
        block.layer.masksToBounds = true
        view.addSubview(block)

        label.frame = CGRect(x: 150, y: 200, width: 200, height: 20)
        label.text = "Hello World!"
        label.textColor = .black
        view.addSubview(label)

        gradient.frame = CGRect(x: 100, y: 300, width: 200, height: 200)
        view.addSubview(gradient)

        self.view = view
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        view.layer.contents
        label.layer.contents
        block.layer.contents
        gradient.layer.contents
        
        //UIView.animate(withDuration: 2.0, animations: {
        //    self.block.transform = CGAffineTransform(scaleX: 0.01, y: 1)
        //})
        block.animateTransform()
        gradient.animateCornerRadius()
    }
}

class Block: UIView {
    override func draw(_ rect: CGRect) {
        UIColor.red.setFill()
        UIBezierPath(rect: bounds).fill()
    }
}

class Gradient: UIView {
    class override var layerClass: AnyClass {
        CAGradientLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let layer = self.layer as! CAGradientLayer
        layer.colors = [UIColor.red.cgColor, UIColor.yellow.cgColor]
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIView {
    func animateTransform() {
        // 3D version of CGAffineTransform(scaleX: 0.01, y: 1)
        let destTransform = CATransform3D(m11: 0.01, m12: 0, m13: 0, m14: 0,
                                          m21: 0, m22: 1, m23: 0, m24: 0,
                                          m31: 0, m32: 0, m33: 1, m34: 0,
                                          m41: 0, m42: 0, m43: 0, m44: 1)
        
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.transform
        animation.toValue = destTransform
        animation.duration = 2
        layer.add(animation, forKey: nil)
        layer.transform = destTransform
    }
    
    func animateCornerRadius() {
        let cornerRadius = 0.5 * bounds.size.width
        
        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = 0
        animation.toValue = cornerRadius
        animation.duration = 2
        layer.add(animation, forKey: nil)
        layer.cornerRadius = cornerRadius
    }
}
