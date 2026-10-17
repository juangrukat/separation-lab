import Foundation
import CoreGraphics

func fixture(width: Double, shift: Double = 0, bright: Bool = false) -> GrayImage {
 let w=500,h=200
 var pixels=[UInt8](repeating:0,count:w*h)
 for y in 0..<h { for x in 0..<w {
  let a=(Double(x)-200.3-shift)/0.8
  let b=(Double(x)-200.3-width-shift)/0.8
  let band=0.5*(tanh(a)-tanh(b))
  pixels[y*w+x]=UInt8(max(0,min(255,(bright ? 35+180*band : 220-180*band).rounded())))
 } }
 return GrayImage(width:w,height:h,pixels:pixels)
}
@main struct Tests {
 static func main() throws {
  var count=0
  for width in [3.2,5.7,12.4,50.3] {
   for bright in [false,true] {
    let points=[CGPoint(x:50,y:50),CGPoint(x:150,y:50),CGPoint(x:200.3,y:100),CGPoint(x:200.3+width,y:100)]
    let r=try Measurement.measure(fixture(width:width,bright:bright),points:points,referenceMM:10)
    let error=abs(r.pixelWidth-width)
    print("width=\(width) polarity=\(bright) fitted=\(r.pixelWidth) error=\(error)")
    if error >= 0.30 { FileHandle.standardError.write(Data("FAIL width=\(width) fitted=\(r.pixelWidth) error=\(error)\n".utf8)) }; precondition(error < 0.30,"Subpixel fixture mismatch")
    precondition(abs(r.millimetres-width*0.1)<0.03)
    count += 1
   }
  }
  let p=[CGPoint(x:50,y:50),CGPoint(x:150,y:50),CGPoint(x:200,y:100),CGPoint(x:220,y:100)]
  do { _=try Measurement.measure(GrayImage(width:500,height:200,pixels:[UInt8](repeating:128,count:100000)),points:p,referenceMM:10);fatalError("Flat image accepted") } catch { count += 1 }
  do { _=try Measurement.measure(fixture(width:20),points:p,referenceMM:0);fatalError("Zero scale accepted") } catch { count += 1 }
  var unresolved=p;unresolved[3]=CGPoint(x:201,y:100)
  do { _=try Measurement.measure(fixture(width:1),points:unresolved,referenceMM:10);fatalError("Unresolved image accepted") } catch { count += 1 }
  var asym=[UInt8](repeating:0,count:500*200)
  for y in 0..<200 { for x in 0..<500 {
   let l=0.5*(1+tanh((Double(x)-200.3)/0.8)),r=0.5*(1+tanh((Double(x)-220.3)/0.8))
   asym[y*500+x]=UInt8(max(0,min(255,(220-190*l+70*r).rounded())))
  } }
  let asymmetric=GrayImage(width:500,height:200,pixels:asym)
  let edgePoints=[CGPoint(x:50,y:50),CGPoint(x:150,y:50),CGPoint(x:200.3,y:100),CGPoint(x:220.3,y:100)]
  let ar=try Measurement.measure(asymmetric,points:edgePoints,referenceMM:10)
  precondition(abs(ar.pixelWidth-20)<0.3,"Unequal material brightness must be supported");count += 1
  let displacedPoints=[CGPoint(x:50,y:50),CGPoint(x:150,y:50),CGPoint(x:192.3,y:100),CGPoint(x:228.3,y:100)]
  let dr=try Measurement.measure(fixture(width:20),points:displacedPoints,referenceMM:10)
  precondition(abs(dr.pixelWidth-20)<0.3,"Recover modest tap placement error");count += 1
  let local=try Measurement.cutout(asymmetric,points:edgePoints,referenceMM:10)
  precondition(abs(local.pixelWidth-20)<0.5 && local.acceptedSections>=5);count += 1
  var obstruction=asym
  for y in 0..<200 { for x in 205..<216 { obstruction[y*500+x]=170 } }
  let obstructed=try Measurement.cutout(GrayImage(width:500,height:200,pixels:obstruction),points:edgePoints,referenceMM:10)
  precondition(abs(obstructed.pixelWidth-20)<1 && obstructed.method.contains("cutout"),"Interior tab must not redefine outer width");count += 1
  do { _=try Measurement.cutout(GrayImage(width:500,height:200,pixels:[UInt8](repeating:128,count:100000)),points:edgePoints,referenceMM:10);fatalError("Blank cutout accepted") } catch { count += 1 }
  let tw=180,th=180
  var texture=[UInt8](repeating:0,count:tw*th)
  var seed:UInt64=12345
  for i in texture.indices { seed=seed &* 6364136223846793005 &+ 1;texture[i]=UInt8((seed >> 32) & 255) }
  let source=GrayImage(width:tw,height:th,pixels:texture)
  var shifted=[UInt8](repeating:0,count:tw*th)
  for y in 3..<th { for x in 4..<tw { shifted[y*tw+x]=texture[(y-3)*tw+x-4] } }
  let destination=GrayImage(width:tw,height:th,pixels:shifted)
  let marks=[CGPoint(x:45,y:45),CGPoint(x:125,y:45),CGPoint(x:65,y:110),CGPoint(x:85,y:110)]
  let visionShift=try ImageRegistration.shift(reference:source,target:destination)
  print("Vision shift: \(visionShift)")
  precondition(abs(visionShift.x-4)<0.6 && abs(visionShift.y-3)<0.6,"Registration direction and scale");count += 1
  let manual=try Measurement.manual(points:edgePoints,referenceMM:10)
  precondition(manual.acceptedSections==0 && abs(manual.millimetres-2)<0.001 && manual.method.contains("Manual"));count += 1
  let tracked=try Measurement.track(reference:source,target:destination,points:marks,step:1)
  for (p,q) in zip(marks,tracked) { precondition(abs(q.x-p.x-4)<0.01 && abs(q.y-p.y-3)<0.01) };count += 1
  var far=[UInt8](repeating:0,count:tw*th)
  for y in 22..<th { for x in 25..<tw { far[y*tw+x]=texture[(y-22)*tw+x-25] } }
  let distant=GrayImage(width:tw,height:th,pixels:far)
  let global=try ImageRegistration.shift(reference:source,target:distant)
  let recovered=try Measurement.track(reference:source,target:distant,points:marks,step:1,globalShift:global)
  for (p,q) in zip(marks,recovered) { precondition(abs(q.x-p.x-25)<0.01 && abs(q.y-p.y-22)<0.01,"Whole-frame alignment must recover movement beyond the old search window") };count += 1
  let refined=Measurement.refineTracking(reference:source,target:destination,original:marks,tracked:tracked.map { CGPoint(x:$0.x+1,y:$0.y-1) },radius:3)
  for (p,q) in zip(marks,refined) { precondition(abs(q.x-p.x-4)<0.01 && abs(q.y-p.y-3)<0.01) };count += 1
  precondition(Measurement.median([1,2,3,4])==2.5)
  print("PASS: \(count+1) checks")
 }
}
