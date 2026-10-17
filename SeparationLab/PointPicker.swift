import SwiftUI

struct PointPicker: UIViewRepresentable {
    let image: UIImage
    let points: [CGPoint]
    var resetToken:Int = 0
    let onTap: (CGPoint) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class ScrollSurface:UIScrollView {
        var onLayout:(()->Void)?
        override func layoutSubviews() { super.layoutSubviews();onLayout?() }
    }
    func makeUIView(context:Context) -> ScrollSurface {
        let scroll = ScrollSurface(); scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1;scroll.maximumZoomScale = 16
        scroll.keyboardDismissMode = .onDrag
        scroll.backgroundColor = .black;scroll.bouncesZoom = false
        let content = UIImageView(image:image);content.isUserInteractionEnabled = true
        content.contentMode = .scaleToFill;content.tag = 99;scroll.addSubview(content)
        context.coordinator.scroll = scroll;context.coordinator.imageView = content
        let coordinator=context.coordinator
        scroll.onLayout = { [weak coordinator] in coordinator?.layout() }
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:)))
        content.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.zoom(_:)))
        doubleTap.numberOfTapsRequired = 2;content.addGestureRecognizer(doubleTap);tap.require(toFail:doubleTap)
        return scroll
    }
    func updateUIView(_ scroll:ScrollSurface,context:Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReset != resetToken {
            context.coordinator.lastReset=resetToken
            context.coordinator.size = .zero
        }
        context.coordinator.layout()
        context.coordinator.draw()
    }
    final class Coordinator: NSObject,UIScrollViewDelegate {
        var parent: PointPicker
        weak var scroll: UIScrollView?
        weak var imageView: UIImageView?
        var fit: CGFloat = 1
        var size = CGSize.zero
        var lastReset=0
        private var layingOut=false
        init(_ parent:PointPicker) { self.parent = parent }
        func layout() {
            guard !layingOut,let scroll,let v=imageView,scroll.bounds.width>0,scroll.bounds.height>0 else { return }
            guard size != scroll.bounds.size else { return }
            layingOut=true
            defer { layingOut=false }
            size=scroll.bounds.size
            scroll.setZoomScale(1,animated:false)
            let imageSize=parent.image.size
            fit=min(size.width/imageSize.width,size.height/imageSize.height)
            v.frame=CGRect(origin:.zero,size:CGSize(width:imageSize.width*fit,height:imageSize.height*fit))
            scroll.contentSize=v.bounds.size
            center()
            scroll.contentOffset=CGPoint(x:-scroll.contentInset.left,y:-scroll.contentInset.top)
            draw()
        }
        func viewForZooming(in scrollView:UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView:UIScrollView) { center();draw() }
        func center() {
            guard let scroll,let v = imageView else { return }
            scroll.contentInset = UIEdgeInsets(top:max(0,(scroll.bounds.height-v.frame.height)/2),left:max(0,(scroll.bounds.width-v.frame.width)/2),bottom:0,right:0)
        }
        @objc func tap(_ gesture:UITapGestureRecognizer) {
            guard let v = imageView else { return }
            let p = gesture.location(in:v)
            parent.onTap(CGPoint(x:p.x/fit,y:p.y/fit))
        }
        @objc func zoom(_ gesture:UITapGestureRecognizer) {
            guard let scroll,let v = imageView else { return }
            if scroll.zoomScale > 3 { scroll.setZoomScale(1,animated:true) }
            else {
                let p = gesture.location(in:v),z:CGFloat = 6
                scroll.zoom(to:CGRect(x:p.x-scroll.bounds.width/z/2,y:p.y-scroll.bounds.height/z/2,width:scroll.bounds.width/z,height:scroll.bounds.height/z),animated:true)
            }
        }
        func draw() {
            guard let v = imageView else { return }
            v.layer.sublayers?.filter { $0.name == "point" }.forEach { $0.removeFromSuperlayer() }
            let zoom = scroll?.zoomScale ?? 1
            let colors: [UIColor] = [.systemTeal,.systemTeal,.systemOrange,.systemOrange]
            for (i,p) in parent.points.enumerated() {
                let c = CGPoint(x:p.x*fit,y:p.y*fit),r = 9/zoom
                let shape = CAShapeLayer();shape.name = "point"
                let path = UIBezierPath(ovalIn:CGRect(x:c.x-r,y:c.y-r,width:2*r,height:2*r))
                path.move(to:CGPoint(x:c.x-r*1.6,y:c.y));path.addLine(to:CGPoint(x:c.x+r*1.6,y:c.y))
                path.move(to:CGPoint(x:c.x,y:c.y-r*1.6));path.addLine(to:CGPoint(x:c.x,y:c.y+r*1.6))
                shape.path = path.cgPath;shape.strokeColor = colors[i].cgColor
                shape.fillColor = UIColor.clear.cgColor;shape.lineWidth = 1.5/zoom;v.layer.addSublayer(shape)
                let label = CATextLayer();label.name = "point";label.string = ["R1","R2","E1","E2"][i]
                label.foregroundColor = colors[i].cgColor;label.fontSize = 13/zoom;label.contentsScale = UIScreen.main.scale*zoom
                label.frame = CGRect(x:c.x+(i==2 ? -42:12)/zoom,y:c.y-23/zoom,width:35/zoom,height:20/zoom);v.layer.addSublayer(label)
            }
            for pair in [[0,1],[2,3]] where parent.points.count > pair[1] {
                let a = parent.points[pair[0]],b = parent.points[pair[1]]
                let line = CAShapeLayer();line.name = "point"
                let path = UIBezierPath();path.move(to:CGPoint(x:a.x*fit,y:a.y*fit));path.addLine(to:CGPoint(x:b.x*fit,y:b.y*fit))
                line.path = path.cgPath;line.strokeColor = colors[pair[0]].cgColor;line.lineWidth = 1/zoom
                line.lineDashPattern = [4/zoom,4/zoom].map { NSNumber(value:Double($0)) };v.layer.addSublayer(line)
            }
        }
    }
}
