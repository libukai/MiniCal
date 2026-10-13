import Foundation
import CoreGraphics
import CoreText
import ImageIO
let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes = [(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),(128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),(512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]
for (size,name) in sizes {
    let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    let outer=CGPath(roundedRect:CGRect(x:64,y:64,width:896,height:896),cornerWidth:190,cornerHeight:190,transform:nil)
    ctx.setFillColor(CGColor(red:0.96,green:0.96,blue:0.97,alpha:1));ctx.addPath(outer);ctx.fillPath()
    ctx.saveGState();ctx.addPath(outer);ctx.clip()
    ctx.setFillColor(CGColor(red:0.9569,green:0.2627,blue:0.2118,alpha:1));ctx.fill(CGRect(x:64,y:688,width:896,height:272));ctx.restoreGState()
    let font=CTFontCreateWithName("HelveticaNeue-Bold" as CFString,480,nil)
    let line=CTLineCreateWithAttributedString(NSAttributedString(string:"12",attributes:[kCTFontAttributeName as NSAttributedString.Key:font,kCTForegroundColorAttributeName as NSAttributedString.Key:CGColor(red:0.2157,green:0.2784,blue:0.3098,alpha:1)]))
    let bounds=CTLineGetBoundsWithOptions(line,[.useGlyphPathBounds])
    ctx.textPosition=CGPoint(x:(1024-bounds.width)/2-bounds.minX,y:232-bounds.minY);CTLineDraw(line,ctx)
    ctx.setFillColor(CGColor(gray:1,alpha:1))
    for x in [CGFloat(300),CGFloat(680)] {ctx.addPath(CGPath(roundedRect:CGRect(x:x,y:768,width:46,height:140),cornerWidth:23,cornerHeight:23,transform:nil));ctx.fillPath()}
    let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:out).appendingPathComponent(name) as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dest,ctx.makeImage()!,nil);CGImageDestinationFinalize(dest)
}
