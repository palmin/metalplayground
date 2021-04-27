// Adapted from Metal playground at:
//    https://github.com/irlabs/metal-shader-playground

import Cocoa
import Metal
import MetalKit
import PlaygroundSupport

var options = Options()
options.color = always(NSColor.yellow)
options.scalar = always(0.1)
options.fragmentShaderFunction = """
fragment half4 fragment_shader(RasterizerData in [[stage_in]],
                                    constant float4 &backgroundColor [[ buffer(Color) ]],
                                    constant float &cornerRadius [[ buffer(Scalar) ]],
                                    texture2d<half> colorTexture [[ texture(Texture) ]]) {
            
            // return background color when close enough to corners
            float2 p = in.textureCoordinate;
            float r = cornerRadius;
            float s = 1.0 - r;
            if((p.x < r && p.y < r) || (p.x < r && p.y > s) ||
               (p.x > s && p.y > s) || (p.x > s && p.y < r)) {
                if(min(min(distance(float2(r, r), p), distance(float2(r, s), p)),
                       min(distance(float2(s, r), p), distance(float2(s, s), p))) >= r) {
                  return half4(backgroundColor);
                }
            }

            constexpr sampler textureSampler (mag_filter::linear,
                                              min_filter::linear);
            const half4 colorSample = colorTexture.sample(textureSampler, p);
            return colorSample;
        }
"""
options.draw { context, rect in
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(rect)
}
render(options)

struct Options {
    var frame: ((Double) -> CGRect) = always(CGRect(x: 50, y: 50,
                                                    width: 300, height: 300))
    var transform: ((Double) -> CGAffineTransform) = always(CGAffineTransform.identity)

    var texture: NSImage? = nil
    var color: ((Double) -> NSColor) = always(NSColor.cyan)
    var scalar: ((Double) -> Double) = always(0)
    
    // must contain function defition for fragment_shader()
    var fragmentShaderFunction = """
fragment half4 fragment_shader() {
    return half4(0.0, 0.0, 0.0, 1.0);
}
"""

    static let viewLength = 400.0
}

func render(_ options: Options = Options()) {
    
    // variables set from outside regular code are integer based
    let textureId = 0
    let colorId = 1
    let scalarId = 2
    
    // get handle to GPU device
    let device = MTLCreateSystemDefaultDevice()!

    // create a shader library in source (not precompiled)
    let runtimeLibrary = try! device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;

        // variables set from outside regular code are integer based
        enum {
            Texture = 0,
            Color = 1,
            Scalar = 2,
        };

        struct RasterizerData {
            // The [[position]] attribute qualifier of this member indicates this value is
            // the clip space position of the vertex when this structure is returned from
            // the vertex shader. Coordinates go from -1.0 to +1.0.
            float4 position [[position]];

            // Texture coordinates go from 0.0 to 1.0
            float2 textureCoordinate;
        };

        vertex RasterizerData copy_vertex(
            const device packed_float4* vertex_array [[buffer(0)]],
                                     unsigned int vid [[vertex_id]]) {

            RasterizerData out;
            const float4 where = vertex_array[vid];
            out.position = float4(where[0], where[1], 0.0, 1.0);
            out.textureCoordinate = float2(where[2], where[3]);
            return out;
        }
    """ + options.fragmentShaderFunction, options: nil)
            
    // configure pipeline
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = runtimeLibrary.makeFunction(name: "copy_vertex")
    descriptor.fragmentFunction = runtimeLibrary.makeFunction(name: "fragment_shader")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // framebuffer format

    // compile to MTLPRenderPipelineState
    let renderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

    // create an NSView, with a metal layer as its backing layer.
    let metalLayer = CAMetalLayer()
    metalLayer.device = device
    let length = Options.viewLength
    let view = NSView(frame: NSRect(x: 0, y: 0, width: length, height: length))
    view.layer = metalLayer
    
    // wire up metal view to playground
    PlaygroundPage.current.liveView = view

    // prepare our command buffer and drawable
    let commandQueue = device.makeCommandQueue()
    
    // create the render pass descriptor that starts by clearing with gray
    let rpDesc = MTLRenderPassDescriptor()
    rpDesc.colorAttachments[0].loadAction = .clear
    rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.75, 0.75, 0.75, 1.0)
    
    // load texture from Options or bundle
    let textureLoader = MTKTextureLoader(device: device)
    let textimageImage: NSImage
    if let known = options.texture {
        textimageImage = known
    } else {
        let imageUrl = Bundle.main.url(forResource: "TV-test", withExtension: "png")!
        textimageImage = NSImage(contentsOf: imageUrl)!
    }
    let cgImage = textimageImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let texture = try! textureLoader.newTexture(cgImage: cgImage, options: nil)
    
    // everything above this step is reused for all frames, and everything below
    // is done for each frame
    func renderPass(frame: CGRect,
                    transform: CGAffineTransform,
                    color: NSColor,
                    scalar: Double) {
        // geometry coordinates go from -1 to +1
        let x1 = 2.0 * Double(frame.minX) / Options.viewLength - 1.0
        let x2 = 2.0 * Double(frame.maxX) / Options.viewLength - 1.0
        let y1 = 2.0 * Double(frame.minY) / Options.viewLength - 1.0
        let y2 = 2.0 * Double(frame.maxY) / Options.viewLength - 1.0
        let upperRight = CGPoint(x: x2, y:  y2)
        let lowerLeft = CGPoint(x: x1, y: y1)
        let upperLeft = CGPoint(x: x1, y:  y2)
        let lowerRight = CGPoint(x: x2, y: y1)

        // texture coordinates
        let textureUpperRight = CGPoint(x: 1, y: 0)
        let textureLowerLeft = CGPoint(x: 0, y: 1)
        let textureUpperLeft = CGPoint(x: 0, y: 0)
        let textureLowerRight = CGPoint(x: 1, y: 1)
        
        // mix geometry coordinates (transformed) and
        // texture coordinates (untransformed) in one shared array
        let vertexData = [upperRight, textureUpperRight,
                          lowerLeft, textureLowerLeft,
                          upperLeft, textureUpperLeft,
                          
                          upperRight, textureUpperRight,
                          lowerRight, textureLowerRight,
                          lowerLeft, textureLowerLeft].vertexData(transform)
        
        // use stride instead of size, as this properly reflects memory usage.
        let dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0])
        let vertexArray = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        // create a buffer of render commands
        let buffer: MTLCommandBuffer! = commandQueue?.makeCommandBuffer()
        let drawable = metalLayer.nextDrawable()!
        rpDesc.colorAttachments[0].texture = drawable.texture

        // we feed the encoder with data
        let encoder = buffer.makeRenderCommandEncoder(descriptor: rpDesc)!
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(vertexArray, offset: 0, index: 0)
        
        // set texture argument
        encoder.setFragmentTexture(texture, index: textureId)
        
        // set color argument
        var fragmentColor = vector_float4(Float(color.redComponent), Float(color.greenComponent),
                                          Float(color.blueComponent), Float(color.alphaComponent))
        encoder.setFragmentBytes(&fragmentColor, length: MemoryLayout.size(ofValue: fragmentColor),
                                 index: colorId)
        
        // set scalar argument
        var simdScalar = simd_float1(scalar)
        encoder.setFragmentBytes(&simdScalar, length: MemoryLayout.size(ofValue: simdScalar),
                                 index: scalarId)
        
        // we are ready to draw our 6 / 3 = 2 triangles
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        // show the buffer
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
    
    // to illustrate animations we make the render parameters time-based
    func renderTime(_ time: Double) {
        renderPass(frame: options.frame(time),
                   transform: options.transform(time),
                   color: options.color(time),
                   scalar: options.scalar(time))
    }
    
    // render first frame
    renderTime(0)
    
    // Setup timer for frame updates. A real implementation would use screen-synced
    // rendering instead of purely time-based rendering
    var t = 0.0
    let maxTime = 2.0
    Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
        t += timer.timeInterval
        if t >= maxTime {
            timer.invalidate()
        }
        
        renderTime(t / maxTime)
    }
}

// function that always returns value itself for when we don't want to animate
func always<T>(_ value: T) -> ((Double) -> T) {
    return { _ in value }
}

extension Options {
    // call the draw method setting image
    mutating func draw(_ drawingHandler: @escaping ((CGContext, CGRect) -> Void)) {
        
        // Create a bitmap graphics context of the given size
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        let len = Int(Options.viewLength)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: nil, width: len, height: len,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: bitmapInfo)!

        // draw into contect
        let rect = CGRect(x: 0, y: 0, width: len, height: len)
        drawingHandler(context, rect)
         
        // create image from context
        let size = NSSize(width: len, height: len)
        texture = NSImage(cgImage: context.makeImage()!, size: size)
    }
}

extension Array where Array.Element == CGPoint  {
    // help produce 4 Floats per Point for both geometry coordinates (even points) and
    // texture coordinates (odd points) where only odd ones are transformed
    func vertexData(_ transform: CGAffineTransform) -> [Float] {
        var result = [Float]()
        var index = 0
        for point in self {
            if index % 2 == 0 {
                let transformed = point.applying(transform)
                result.append(Float(transformed.x))
                result.append(Float(transformed.y))
            } else {
                result.append(Float(point.x))
                result.append(Float(point.y))
            }
            
            index += 1
        }
        return result
    }
}
