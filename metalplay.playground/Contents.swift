// Adapted from Metal playground at:
//    https://github.com/irlabs/metal-shader-playground

import Cocoa
import Metal
import MetalKit
import PlaygroundSupport


renderPipeline(fragmentShader: "background_color")

func renderPipeline(fragmentShader: String = "constant_color",
                    backgroundColor: NSColor = NSColor.lightGray) {
    // get the device
    let device = MTLCreateSystemDefaultDevice()!

    // create data & buffer for data source
    let vertexData: [Float] = [
         0.9,  0.9,
        -0.9, -0.9,
        -0.9,  0.9,

         0.9,  0.9,
         0.9, -0.9,
        -0.9, -0.9,
    ]
    let dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0]) // use stride instead of size, as this properly reflects memory usage.
    let vertexArray = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
    // vertex layout descriptor
    let descriptor = MTLRenderPipelineDescriptor()
    
    let textureId = 0
    let backgroundColorId = 1
    let cornerRadiusId = 2
    let strokeWidthId = 3

    // create a shader library in source (not precompiled)
    let runtimeLibrary = try! device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;

        enum {
            Texture = 0,
            BackgroundColor = 1,
            CornerRadius = 2,
            StrokeWidth = 3,
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
            const device packed_float2* vertex_array [[buffer(0)]],
                                     unsigned int vid [[vertex_id]]) {

            RasterizerData out;
            const float2 where = vertex_array[vid];
            out.position = float4(where, 0.0, 1.0);
            out.textureCoordinate = float2(0.5 - 0.5 * where.x,
                                           0.5 - 0.5 * where.y);
            return out;
        }

        fragment half4 constant_color() {
            return half4(0.95, 0.9, 0.1, 1.0);
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

    """, options: nil)

    // vertex & fragment shader
    descriptor.vertexFunction = runtimeLibrary.makeFunction(name: "copy_vertex")
    descriptor.fragmentFunction = runtimeLibrary.makeFunction(name: fragmentShader)

    // framebuffer format
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    // compile to MTLPRenderPipelineState
    let renderPipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

    // create an NSView, with a metal layer as its backing layer.
    let metalLayer = CAMetalLayer()
    metalLayer.device = device
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    view.layer = metalLayer
    PlaygroundPage.current.liveView = view

    // prepare our command buffer and drawable
    let commandQueue = device.makeCommandQueue()
    let buffer: MTLCommandBuffer! = commandQueue?.makeCommandBuffer()
    let drawable = metalLayer.nextDrawable()!
    
    // create the render pass descriptor
    let rpDesc = MTLRenderPassDescriptor()
    rpDesc.colorAttachments[0].texture = drawable.texture
    rpDesc.colorAttachments[0].loadAction = .clear
    rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0)
    
    // load texture
    let textureLoader = MTKTextureLoader(device: device)
    let textureUrl = Bundle.main.url(forResource: "TV-test", withExtension: "png")!
    let texture = try! textureLoader.newTexture(URL: textureUrl, options: nil)
    
    // create a buffer of actual render commands
    let encoder = buffer.makeRenderCommandEncoder(descriptor: rpDesc)!
    encoder.setRenderPipelineState(renderPipeline)
    encoder.setVertexBuffer(vertexArray, offset: 0, index: 0)
    encoder.setFragmentTexture(texture, index: textureId)
    
    // set background color
    let color = backgroundColor
    var fragmentColor = vector_float4(Float(color.redComponent), Float(color.greenComponent),
                                      Float(color.blueComponent), Float(color.alphaComponent))
    encoder.setFragmentBytes(&fragmentColor, length: MemoryLayout.size(ofValue: fragmentColor), index: backgroundColorId)
    
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    
    // show the buffer
    buffer.present(drawable)
    buffer.commit()
}
