import Foundation
import CoreGraphics

struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    func sample(_ x: Double, _ y: Double) -> Double {
        let a = min(max(x, 0), Double(width - 2))
        let b = min(max(y, 0), Double(height - 2))
        let ix = Int(a), iy = Int(b), dx = a - Double(ix), dy = b - Double(iy)
        let k = iy * width + ix
        return (Double(pixels[k]) * (1-dx) + Double(pixels[k+1]) * dx) * (1-dy)
            + (Double(pixels[k+width]) * (1-dx) + Double(pixels[k+width+1]) * dx) * dy
    }
    func thumbnail() -> (GrayImage, Double) {
        let step = max(1, Int(ceil(Double(max(width, height)) / 1100)))
        let w = width / step, h = height / step
        var result = [UInt8](repeating: 0, count: w*h)
        for y in 0..<h { for x in 0..<w { result[y*w+x] = pixels[(y*step)*width+x*step] } }
        return (GrayImage(width: w, height: h, pixels: result), Double(step))
    }
}

enum MeasureError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}

struct FrameMeasurement: Codable {
    let millimetres: Double
    let pixelWidth: Double
    let mmPerPixel: Double
    let sectionSpreadMM: Double
    let acceptedSections: Int
    var refinedEdges: [[Double]]? = nil
    var method: String = "Assisted edge fit"
}

struct MeasurementReport: Codable {
    let created: Date
    let referenceMM: Double
    let points: [[Double]]
    let frames: [FrameMeasurement]
    let rejectedFrames: [String]
    let processing: String
    let imageWidth: Int
    let imageHeight: Int
    let limitations: String
    var mean: Double { frames.map(\.millimetres).reduce(0,+) / Double(frames.count) }
    var range: Double { (frames.map(\.millimetres).max() ?? 0) - (frames.map(\.millimetres).min() ?? 0) }
}

enum Measurement {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x-b.x, a.y-b.y) }
    static func median(_ x: [Double]) -> Double {
        let s = x.sorted(); return s.count % 2 == 0 ? (s[s.count/2-1]+s[s.count/2])/2 : s[s.count/2]
    }
    static func measure(_ image: GrayImage, points: [CGPoint], referenceMM: Double) throws -> FrameMeasurement {
        guard points.count == 4, referenceMM.isFinite, referenceMM > 0 else {
            throw MeasureError.invalid("Choose two reference markings and two material boundaries.")
        }
        let calibration = distance(points[0], points[1])
        guard calibration >= 40 else { throw MeasureError.invalid("Use tape markings farther apart: at least 40 image pixels.") }
        let width = distance(points[2], points[3])
        guard width >= 2 else { throw MeasureError.invalid("The selected boundaries are unresolved. Move closer or use higher detail.") }
        let ux = (points[3].x-points[2].x)/width, uy = (points[3].y-points[2].y)/width
        let radius = min(32, max(1.0, width*0.4))
        func locate(_ p: CGPoint, offset: Double) -> (Double, Double)? {
            let cx = p.x - uy*offset, cy = p.y + ux*offset
            let margin = radius + 3
            guard cx > margin, cy > margin, cx < Double(image.width)-margin, cy < Double(image.height)-margin else { return nil }
            let step = 0.25
            let n = Int(radius*2/step)+1
            var gradients = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let t = -radius+Double(i)*step
                var g = 0.0
                for j in -1...1 {
                    let x = cx+ux*t-uy*Double(j), y = cy+uy*t+ux*Double(j)
                    g += (image.sample(x+ux, y+uy)-image.sample(x-ux, y-uy))/3
                }
                gradients[i] = g
            }
            func score(_ i:Int) -> Double {
                let t = -radius+Double(i)*step
                return abs(gradients[i])*exp(-0.5*pow(t/max(1,radius*0.7),2))
            }
            guard let k = gradients.indices.max(by: { score($0) < score($1) }), k > 0, k < n-1,
                  abs(gradients[k]) >= 10 else { return nil }
            let a = abs(gradients[k-1]), b = abs(gradients[k]), c = abs(gradients[k+1])
            let denom = a-2*b+c
            let delta = abs(denom) > 0.0001 ? max(-0.5,min(0.5,0.5*(a-c)/denom)) : 0
            return (-radius+(Double(k)+delta)*step, gradients[k])
        }
        var widths: [Double] = [],leftOffsets:[Double]=[],rightOffsets:[Double]=[]
        for offset in stride(from: -8.0, through: 8.0, by: 2) {
            if let left = locate(points[2], offset: offset), let right = locate(points[3], offset: offset) {
                let cx = points[2].x-uy*offset,cy = points[2].y+ux*offset
                guard let fitted = fitOpening(image,cx:cx,cy:cy,ux:ux,uy:uy,width:width,left:left.0,right:width+right.0,radius:radius) else { continue }
                let w=fitted.1-fitted.0
                if w > 1, abs(w-width) < radius*1.8 { widths.append(w);leftOffsets.append(fitted.0);rightOffsets.append(fitted.1) }
            }
        }
        guard widths.count >= 5 else { throw MeasureError.invalid("Edge refinement succeeded in only \(widths.count) of 9 sections. Tap E1 or E2 below the photo to reposition that edge. You can also deliberately choose Point-to-point for a manual estimate.") }
        let m = median(widths), scale = referenceMM/calibration
        let mad = median(widths.map { abs($0-m) })
        guard mad <= max(1.5,m*0.2) else { throw MeasureError.invalid("Nearby sections disagree. Choose straighter edges or improve focus.") }
        let l=median(leftOffsets),r=median(rightOffsets)
        return FrameMeasurement(millimetres: m*scale, pixelWidth: m, mmPerPixel: scale,
                                sectionSpreadMM: ((widths.max() ?? m)-(widths.min() ?? m))*scale,
                                acceptedSections: widths.count,
                                refinedEdges:[[points[2].x+ux*l,points[2].y+uy*l],[points[2].x+ux*r,points[2].y+uy*r]])
    }

    static func manual(points:[CGPoint],referenceMM:Double) throws -> FrameMeasurement {
        guard points.count==4,points.allSatisfy({$0.x.isFinite && $0.y.isFinite}),referenceMM.isFinite,referenceMM>0,
              distance(points[0],points[1])>=40,distance(points[2],points[3])>=2 else {
            throw MeasureError.invalid("Choose four distinct points and a positive reference distance. Reference markings must be at least 40 image pixels apart.")
        }
        let scale=referenceMM/distance(points[0],points[1]),width=distance(points[2],points[3])
        return FrameMeasurement(millimetres:width*scale,pixelWidth:width,mmPerPixel:scale,sectionSpreadMM:0,acceptedSections:0,method:"Manual point-to-point · no edge verification")
    }

    /// Locate each outer contour locally. Interior tabs and texture are deliberately
    /// excluded from the edge profiles instead of fitting the entire opening.
    static func cutout(_ image:GrayImage,points:[CGPoint],referenceMM:Double) throws -> FrameMeasurement {
        let selected=try manual(points:points,referenceMM:referenceMM)
        let width=selected.pixelWidth,ux=(points[3].x-points[2].x)/width,uy=(points[3].y-points[2].y)/width
        let radius=min(32,max(3,width*0.25))
        func edge(_ p:CGPoint,offset:Double)->Double? {
            let cx=p.x-uy*offset,cy=p.y+ux*offset
            let margin=radius+7
            guard cx>margin,cy>margin,cx<Double(image.width)-margin,cy<Double(image.height)-margin else { return nil }
            let lo=Int(-radius)-5,hi=Int(radius)+5
            var profile:[Double]=[]
            for i in lo...hi {
                var sum=0.0
                for j in -2...2 { sum += image.sample(cx+ux*Double(i)-uy*Double(j),cy+uy*Double(i)+ux*Double(j)) }
                profile.append(sum/5)
            }
            var smooth=profile
            for i in 2..<(profile.count-2) {
                smooth[i]=(profile[i-2]+4*profile[i-1]+6*profile[i]+4*profile[i+1]+profile[i+2])/16
            }
            var gradient=[Double](repeating:0,count:profile.count)
            for i in 3..<(profile.count-3) { gradient[i]=(smooth[i+1]-smooth[i-1])/2 }
            let candidates=(5..<(profile.count-5)).filter { abs(Double($0+lo))<radius-1 }
            func score(_ k:Int)->Double { abs(gradient[k])*exp(-0.5*pow(Double(k+lo)/max(3,radius),2)) }
            guard let k=candidates.max(by:{score($0)<score($1)}),abs(gradient[k])>3 else { return nil }
            let a=abs(gradient[k-1]),b=abs(gradient[k]),c=abs(gradient[k+1]),denom=a-2*b+c
            let delta=abs(denom)>0.0001 ? min(0.5,max(-0.5,0.5*(a-c)/denom)):0
            return Double(k+lo)+delta
        }
        var left:[Double]=[],right:[Double]=[],widths:[Double]=[]
        for offset in stride(from:-8.0,through:8.0,by:2) {
            guard let a=edge(points[2],offset:offset),let b=edge(points[3],offset:offset) else { continue }
            let w=width+b-a
            if w>2 { left.append(a);right.append(b);widths.append(w) }
        }
        guard widths.count>=5 else { throw MeasureError.invalid("The two outer contours could not be located locally. Reposition E1 and E2 on straight sections of the cutout rim; avoid rounded corners and glare.") }
        let m=median(widths),mad=median(widths.map { abs($0-m) })
        guard mad<max(2,m*0.03) else { throw MeasureError.invalid("Cutout contours vary across nearby sections. Move the orange line away from a corner or reflection.") }
        let l=median(left),r=median(right)
        return FrameMeasurement(millimetres:m*selected.mmPerPixel,pixelWidth:m,mmPerPixel:selected.mmPerPixel,
            sectionSpreadMM:((widths.max() ?? m)-(widths.min() ?? m))*selected.mmPerPixel,acceptedSections:widths.count,
            refinedEdges:[[points[2].x+ux*l,points[2].y+uy*l],[points[3].x+ux*r,points[3].y+uy*r]],
            method:"Full cutout · local contour fit · verify orange markers")
    }

    // Fit both blurred boundaries jointly to native pixel centres. This avoids
    // bias from treating the two overlapping gradient peaks independently.
    private static func fitOpening(_ image:GrayImage,cx:Double,cy:Double,ux:Double,uy:Double,width:Double,left:Double,right:Double,radius:Double) -> (Double,Double)? {
        let pad = max(6,radius+3)
        var samples:[(Double,Double)] = [],seen=Set<Int>()
        let strideSize = max(1,Int((width+2*pad)/250))
        for i in stride(from:Int(-pad),through:Int(width+pad),by:strideSize) {
            for n in -1...1 {
                let x=Int((cx+ux*Double(i)-uy*Double(n)).rounded()),y=Int((cy+uy*Double(i)+ux*Double(n)).rounded())
                guard x>=0,y>=0,x<image.width,y<image.height else { continue }
                let k=y*image.width+x
                if seen.insert(k).inserted { samples.append(((Double(x)-cx)*ux+(Double(y)-cy)*uy,Double(image.pixels[k]))) }
            }
        }
        guard samples.count > 12 else { return nil }
        func loss(_ p:[Double]) -> Double {
            let l=p[0],r=p[1],s=p[2]
            guard abs(l)<=radius*1.6,abs(r-width)<=radius*1.6,r-l>0.8,s>=0.25,s<=3 else { return .infinity }
            var sl=0.0,sr=0.0,sll=0.0,srr=0.0,slr=0.0,sy=0.0,sly=0.0,sry=0.0,syy=0.0
            for (t,y) in samples {
                let a=0.5*(1+tanh((t-l)/s)),b=0.5*(1+tanh((t-r)/s))
                sl += a;sr += b;sll += a*a;srr += b*b;slr += a*b;sy += y;sly += a*y;sry += b*y;syy += y*y
            }
            let n=Double(samples.count),vll=sll-sl*sl/n,vrr=srr-sr*sr/n,vlr=slr-sl*sr/n
            let cyl=sly-sl*sy/n,cyr=sry-sr*sy/n,det=vll*vrr-vlr*vlr
            guard det>0.01 else { return .infinity }
            let a=(cyl*vrr-cyr*vlr)/det,b=(cyr*vll-cyl*vlr)/det
            guard abs(a)>15,abs(b)>15 else { return .infinity }
            let base=(sy-a*sl-b*sr)/n
            return max(0,(syy-base*sy-a*sly-b*sry)/n)
        }
        var best:[Double]=[left,right,0.8],bestLoss=Double.infinity
        for sigma in [0.4,0.8,1.6] {
            var p=[left,right,sigma],score=loss([left,right,sigma]),step=0.5
            for _ in 0..<35 {
                var improved=false
                for axis in 0..<3 {
                    for sign in [-1.0,1.0] {
                        var q=p;q[axis] += step*sign
                        let next=loss(q)
                        if next<score { p=q;score=next;improved=true }
                    }
                }
                if !improved { step *= 0.5 }
                if step<0.005 { break }
            }
            if score<bestLoss { best=p;bestLoss=score }
        }
        guard bestLoss.isFinite,bestLoss<225 else { return nil }
        return (best[0],best[1])
    }

    // Track each selected feature independently in a thumbnail. Reject flat patches,
    // low correlation, or geometry changes rather than transferring a stale scale.
    static func track(reference: GrayImage, target: GrayImage, points: [CGPoint], step: Double,globalShift:CGPoint? = nil) throws -> [CGPoint] {
        guard reference.width == target.width, reference.height == target.height else { throw MeasureError.invalid("Frame dimensions changed.") }
        let r = 9, search = globalShift == nil ? 18 : 7
        let gx=Int((globalShift?.x ?? 0).rounded()),gy=Int((globalShift?.y ?? 0).rounded())
        var mapped: [CGPoint] = []
        for p in points {
            let px = Int((p.x/step).rounded()), py = Int((p.y/step).rounded())
            guard px > r,py > r,px < reference.width-r,py < reference.height-r,
                  px+gx > r+search,py+gy > r+search,px+gx < target.width-r-search,py+gy < target.height-r-search else {
                throw MeasureError.invalid("A selected point is too close to the image boundary for tracking.")
            }
            var patch: [Double] = []
            for y in -r...r { for x in -r...r { patch.append(Double(reference.pixels[(py+y)*reference.width+px+x])) } }
            let mean = patch.reduce(0,+)/Double(patch.count)
            patch = patch.map { $0-mean }
            let energy = patch.map { $0*$0 }.reduce(0,+)
            guard energy > Double(patch.count)*25 else { throw MeasureError.invalid("Insufficient texture near a selected point to track the next frame.") }
            var best = -1.0, bx = 0, by = 0
            for dy in -search...search { for dx in -search...search {
                var sum = 0.0, sum2 = 0.0, cross = 0.0, k = 0
                for y in -r...r { for x in -r...r {
                    let v = Double(target.pixels[(py+gy+dy+y)*target.width+px+gx+dx+x])
                    sum += v; sum2 += v*v; cross += patch[k]*v; k += 1
                } }
                let e = sum2-sum*sum/Double(patch.count)
                let score = cross/sqrt(max(energy*e,1))
                if score > best+0.00001 || (abs(score-best) <= 0.00001 && dx*dx+dy*dy < bx*bx+by*by) { best = score; bx = dx; by = dy }
            } }
            guard best > 0.90, abs(bx) < search, abs(by) < search else { throw MeasureError.invalid("Frame moved too much or the appearance changed. Support the phone and recapture.") }
            mapped.append(CGPoint(x: p.x+Double(gx+bx)*step,y: p.y+Double(gy+by)*step))
        }
        let a = distance(points[0],points[1]), b = distance(mapped[0],mapped[1])
        guard abs(b/a-1) < 0.015 else { throw MeasureError.invalid("Reference scale changed between frames. Recapture with the phone supported.") }
        let u = CGPoint(x: points[1].x-points[0].x,y: points[1].y-points[0].y)
        let v = CGPoint(x: mapped[1].x-mapped[0].x,y: mapped[1].y-mapped[0].y)
        let angle = abs(atan2(u.x*v.y-u.y*v.x,u.x*v.x+u.y*v.y))
        guard angle < 0.015 else { throw MeasureError.invalid("Phone rotation changed between frames.") }
        return mapped
    }

    static func refineTracking(reference:GrayImage,target:GrayImage,original:[CGPoint],tracked:[CGPoint],radius:Int) -> [CGPoint] {
        zip(original,tracked).map { p,q in
            let r = 6, px = Int(p.x.rounded()),py = Int(p.y.rounded())
            let qx = Int(q.x.rounded()),qy = Int(q.y.rounded())
            guard px > r,py > r,px < reference.width-r,py < reference.height-r,
                  qx > r+radius,qy > r+radius,qx < target.width-r-radius,qy < target.height-r-radius else { return q }
            var patch:[Double] = []
            for y in -r...r { for x in -r...r { patch.append(Double(reference.pixels[(py+y)*reference.width+px+x])) } }
            let mean = patch.reduce(0,+)/Double(patch.count)
            patch = patch.map { $0-mean };let energy = patch.map { $0*$0 }.reduce(0,+)
            var best = -1.0,bx = 0,by = 0
            for dy in -radius...radius { for dx in -radius...radius {
                var sum = 0.0,sum2 = 0.0,cross = 0.0,k = 0
                for y in -r...r { for x in -r...r {
                    let value = Double(target.pixels[(qy+dy+y)*target.width+qx+dx+x])
                    sum += value;sum2 += value*value;cross += value*patch[k];k += 1
                } }
                let score = cross/sqrt(max(1,energy*(sum2-sum*sum/Double(patch.count))))
                if score > best+0.00001 || (abs(score-best) <= 0.00001 && dx*dx+dy*dy < bx*bx+by*by) { best = score;bx = dx;by = dy }
            } }
            return CGPoint(x:p.x+Double(qx+bx-px),y:p.y+Double(qy+by-py))
        }
    }
}
