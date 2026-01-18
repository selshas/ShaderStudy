using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class CustomBlitRenderPass : ScriptableRenderPass
{
    private Material material;
    private int propId_color;
    private Color color;

    private class PassData
    {
        public Material material;
        public TextureHandle cameraTex;
    }

    public CustomBlitRenderPass(RenderPassEvent renderPassEvent, Material material, Color color)
    {
        this.renderPassEvent = renderPassEvent;
        this.material = material;
        this.color = color;

        this.propId_color = Shader.PropertyToID("_Color");
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameContext)
    {
        var cameraData = frameContext.Get<UniversalCameraData>();

        var srcTex = UniversalRenderer.CreateRenderGraphTexture(
            renderGraph, 
            new RenderTextureDescriptor(cameraData.scaledWidth, cameraData.scaledHeight),
            "srcTex",
            true,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp
        );

        using (var grphBuilder = renderGraph.AddRasterRenderPass<PassData>("Custom Render Pass - CameraCopy", out var passData))
        {
            var frameData = frameContext.Get<UniversalResourceData>();

            passData.cameraTex = frameData.cameraColor;

            grphBuilder.SetRenderAttachment(srcTex, 0);
            grphBuilder.SetRenderFunc(static (PassData passData, RasterGraphContext context) => {
                Blitter.BlitTexture(context.cmd, passData.cameraTex, new Vector4(1.0f, 1.0f, 0, 0), 0, true);
            });
        }

        using (var grphBuilder = renderGraph.AddRasterRenderPass<PassData>("Custom Render Pass - ColorTint", out var passData))
        {
            var frameData = frameContext.Get<UniversalResourceData>();

            passData.material = material;
            material.SetColor(propId_color, color);
            passData.cameraTex = frameData.cameraColor;

            grphBuilder.UseTexture(in srcTex);
            grphBuilder.SetRenderAttachment(passData.cameraTex, 0);
            grphBuilder.SetRenderFunc(static (PassData passData, RasterGraphContext context) => {
                Blitter.BlitTexture(context.cmd, passData.cameraTex, new Vector4(1.0f, 1.0f, 0, 0), passData.material, 0);
            });
        }
    }
}

public class CustomBlitRenderFeature : ScriptableRendererFeature
{
    private CustomBlitRenderPass customRenderPass;

    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
    public Material material;
    public Color color = Color.white;

    public override void Create()
    {
        customRenderPass = new CustomBlitRenderPass(renderPassEvent, new Material(material), color);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(customRenderPass);
    }
}
