// Adapted from Metal playground at:
//    https://github.com/irlabs/metal-shader-playground

import Cocoa
import Metal
import MetalKit
import PlaygroundSupport

var options = Options()
options.setOrigin(CGPoint(x: 100, y: 50))
options.fragmentShaderFunction = """
    fragment half4 fragment_shader(RasterizerData in [[stage_in]],
                                        texture2d<half> colorTexture [[ texture(Texture) ]]) {
                constexpr sampler textureSampler (mag_filter::linear,
                                                  min_filter::linear);
                const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
                return colorSample;
            }

"""
options.scalar = { time in 0.5 * time }
options.color = { time in NSColor(red: CGFloat(1.0 - time), green: CGFloat(time),
                                  blue: 1, alpha: 1)}

render(options)

struct Options {
    var texture: NSImage? = nil
    var color: ((Double) -> NSColor) = always(NSColor.cyan)
    var scalar: ((Double) -> Double) = always(0)

    var transform: ((Double) -> CGAffineTransform) = always(CGAffineTransform.identity)
    
    // must contain function defition for fragment_shader()
    var fragmentShaderFunction = """
fragment half4 fragment_shader() {
    return half4(0, 0, 0, 1.0);
}
"""

    static let viewLength = 400.0
}

func render(_ options: Options = Options()) {
    
    // variables set from outside regular code are integer based
    let textureId = 0
    let colorId = 1
    let scalarId = 2

    // create a shader library in source (not precompiled)
    let device = MTLCreateSystemDefaultDevice()!
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
            
    // vertex layout descriptor
    let descriptor = MTLRenderPipelineDescriptor()

    // vertex & fragment shader
    descriptor.vertexFunction = runtimeLibrary.makeFunction(name: "copy_vertex")
    descriptor.fragmentFunction = runtimeLibrary.makeFunction(name: "fragment_shader")

    // framebuffer format
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    // compile to MTLPRenderPipelineState
    let renderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

    // create an NSView, with a metal layer as its backing layer.
    let metalLayer = CAMetalLayer()
    metalLayer.device = device
    let length = Options.viewLength
    let view = NSView(frame: NSRect(x: 0, y: 0, width: length, height: length))
    view.layer = metalLayer
    PlaygroundPage.current.liveView = view

    // prepare our command buffer and drawable
    let commandQueue = device.makeCommandQueue()
    
    // create the render pass descriptor that starts by clearing with gray
    let rpDesc = MTLRenderPassDescriptor()
    rpDesc.colorAttachments[0].loadAction = .clear
    rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0)
    
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
    func renderPass(color: NSColor, transform: CGAffineTransform, scalar: Double) {
        // calculate geometry
        let upperRight = CGPoint(x: 1.0, y:  1.0)
        let lowerLeft = CGPoint(x: -1.0, y: -1.0)
        let upperLeft = CGPoint(x: -1.0, y:  1.0)
        let lowerRight = CGPoint(x: 1.0, y: -1.0)

        let vertexData = [upperRight, lowerLeft, upperLeft,
                          upperRight, lowerRight, lowerLeft].vertexData(transform)
        
        // use stride instead of size, as this properly reflects memory usage.
        let dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0])
        let vertexArray = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        // create a buffer of render commands
        let buffer: MTLCommandBuffer! = commandQueue?.makeCommandBuffer()
        let drawable = metalLayer.nextDrawable()!
        rpDesc.colorAttachments[0].texture = drawable.texture

        let encoder = buffer.makeRenderCommandEncoder(descriptor: rpDesc)!
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(vertexArray, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: textureId)
        
        // set background color
        var fragmentColor = vector_float4(Float(color.redComponent), Float(color.greenComponent),
                                          Float(color.blueComponent), Float(color.alphaComponent))
        encoder.setFragmentBytes(&fragmentColor, length: MemoryLayout.size(ofValue: fragmentColor),
                                 index: colorId)
        
        // set corner radius, where we cheat a little since size never changes
        var simdScalar = simd_float1(scalar)
        encoder.setFragmentBytes(&simdScalar, length: MemoryLayout.size(ofValue: simdScalar),
                                 index: scalarId)
        
        // we are ready to draw
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        // show the buffer
        buffer.present(drawable)
        buffer.commit()
    }
    
    // to illustrate animations we make the render parameters time-based
    func renderTime(_ time: Double) {
        renderPass(color: options.color(time),
                   transform: options.transform(time),
                   scalar: options.scalar(time))
    }
    
    // render first frame
    renderTime(0)
    
    // Setup timer for frame updates. A real implementation would use screen-synced rendering
    // instead of purely time-based rendering
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
    // set transform to enforce this origin for entire render
    mutating func setOrigin(_ origin: CGPoint) {
        let tx = 2.0 * origin.x / CGFloat(Options.viewLength)
        let ty = -2.0 * origin.y / CGFloat(Options.viewLength)
        transform = always(CGAffineTransform(translationX: tx, y: ty))
    }
}

extension Array where Array.Element == CGPoint  {
    // help produce 4 Floats per Point for both geometry coordinates and
    // texture coordinates
    func vertexData(_ transform: CGAffineTransform) -> [Float] {
        var result = [Float]()
        for point in self {
            let transformed = point.applying(transform)
            result.append(Float(transformed.x))
            result.append(Float(transformed.y))
   
            // geometry coordinates go from -1 to +1 but texture
            // coordinates from from 0.0 to 1.0
            result.append(Float(0.5 + 0.5 * point.x))
            result.append(Float(0.5 - 0.5 * point.y))
        }
        return result
    }
}
