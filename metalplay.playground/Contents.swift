// Adapted from Metal playground at:
//    https://github.com/irlabs/metal-shader-playground

import Cocoa
import Metal
import MetalKit
import PlaygroundSupport

var options = Options()
//options.transform = { t in CGAffineTransform(scaleX: 1.0 - CGFloat(t), y: 1)}

options.cornerRadius = { t in Float(200.0 * t)}
options.shaderCode = """
fragment half4 constant_color() {
    return half4(0.95, 0.9, 0.1, 1.0);
}
"""

render(options)
//render(fragmentShader: "background_color",
//               backgroundColor: { t in NSColor(calibratedRed: CGFloat(t), green: 0, blue: 1, alpha: 1) })

struct Options {
    var fragmentShader = "sample_layer"
    var shaderCode = ""
    
    var image: NSImage? = nil
    var backgroundColor: ((Double) -> NSColor) = always(NSColor.cyan)
    var cornerRadius: ((Double) -> Float) = always(0)

    var transform: ((Double) -> CGAffineTransform) = always(CGAffineTransform.identity)
}

func render(_ options: Options = Options()) {
    // get the device
    let device = MTLCreateSystemDefaultDevice()!
        
    // vertex layout descriptor
    let descriptor = MTLRenderPipelineDescriptor()
    
    let textureId = 0
    let backgroundColorId = 1
    let cornerRadiusId = 2

    // create a shader library in source (not precompiled)
    let runtimeLibrary = try! device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;

        enum {
            Texture = 0,
            BackgroundColor = 1,
            CornerRadius = 2,
        };

        struct RasterizerData {
            // The [[position]] attribute qualifier of this member indicates this value is
            // the clip space position of the vertex when this structure is returned from
            // the vertex shader
            float4 position [[position]];

            // Since this member does not have a special attribute qualifier, the rasterizer
            // will interpolate its value with values of other vertices making up the triangle
            // and pass that interpolated value to the fragment shader for each fragment in
            // that triangle.
            float2 textureCoordinate;
        };

        vertex RasterizerData copy_vertex(
            const device packed_float4* vertex_array [[buffer(0)]],
                                     unsigned int vid [[vertex_id]]) {

            RasterizerData out;
            const float4 where = vertex_array[vid];
            out.position = float4(where[0], where[1], 0.0, 1.0);
            out.textureCoordinate = float2(0.5 + 0.5 * where[2],
                                           0.5 - 0.5 * where[3]);
            return out;
        }

        fragment half4 background_color(constant float4 &color [[ buffer(BackgroundColor) ]]) {
            return half4(color);
        }

        fragment half4 gradient_color(RasterizerData in [[stage_in]]) {
            return half4(in.textureCoordinate.x,
                         in.textureCoordinate.y, 0.05, 1.0);
        }

        fragment half4 sample_color(RasterizerData in [[stage_in]],
                                    texture2d<half> colorTexture [[ texture(Texture) ]]) {
            constexpr sampler textureSampler (mag_filter::linear,
                                              min_filter::linear);
            const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
            return colorSample;
        }

        fragment half4 sample_layer(RasterizerData in [[stage_in]],
                                    constant float4 &backgroundColor [[ buffer(BackgroundColor) ]],
                                    constant float &cornerRadius [[ buffer(CornerRadius) ]],
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

    """ + options.shaderCode, options: nil)

    // vertex & fragment shader
    descriptor.vertexFunction = runtimeLibrary.makeFunction(name: "copy_vertex")
    descriptor.fragmentFunction = runtimeLibrary.makeFunction(name: options.fragmentShader)

    // framebuffer format
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    // compile to MTLPRenderPipelineState
    let renderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

    // create an NSView, with a metal layer as its backing layer.
    let metalLayer = CAMetalLayer()
    metalLayer.device = device
    let viewLength = CGFloat(400)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: viewLength, height: viewLength))
    view.layer = metalLayer
    PlaygroundPage.current.liveView = view

    // prepare our command buffer and drawable
    let commandQueue = device.makeCommandQueue()
    
    // create the render pass descriptor
    let rpDesc = MTLRenderPassDescriptor()
    rpDesc.colorAttachments[0].loadAction = .clear
    rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0)
    
    // load texture
    let textureLoader = MTKTextureLoader(device: device)
    let textimageImage: NSImage
    if let known = options.image {
        textimageImage = known
    } else {
        let imageUrl = Bundle.main.url(forResource: "TV-test", withExtension: "png")!
        textimageImage = NSImage(contentsOf: imageUrl)!
    }
    let cgImage = textimageImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let texture = try! textureLoader.newTexture(cgImage: cgImage, options: nil)
    
    func renderPass(color: NSColor, transform: CGAffineTransform, radius: Float) {
        // calculate geometry
        let upperRight = CGPoint(x: 1.0, y:  1.0)
        let lowerLeft = CGPoint(x: -1.0, y: -1.0)
        let upperLeft = CGPoint(x: -1.0, y:  1.0)
        let lowerRight = CGPoint(x: 1.0, y: -1.0)

        let vertexData = [upperRight, lowerLeft, upperLeft,
                          upperRight, lowerRight, lowerLeft].vertexData(transform)
        let dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0]) // use stride instead of size, as this properly reflects memory usage.
        let vertexArray = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        // create a buffer of actual render commands
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
                                 index: backgroundColorId)
        
        // set corner radius, where we cheat a little since size never changes
        var cornerRadius = simd_float1(radius / Float(viewLength))
        encoder.setFragmentBytes(&cornerRadius, length: MemoryLayout.size(ofValue: cornerRadius),
                                 index: cornerRadiusId)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        // show the buffer
        buffer.present(drawable)
        buffer.commit()
    }
    
    func renderTime(_ time: Double) {
        renderPass(color: options.backgroundColor(time),
                   transform: options.transform(time),
                   radius: options.cornerRadius(time))
    }
    renderTime(0)
    
    // setup timer for animations
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

extension Array where Array.Element == CGPoint  {
    func vertexData(_ transform: CGAffineTransform) -> [Float] {
        var result = [Float]()
        for point in self {
            let transformed = point.applying(transform)
            result.append(Float(transformed.x))
            result.append(Float(transformed.y))
            result.append(Float(point.x))
            result.append(Float(point.y))
        }
        return result
    }
}
