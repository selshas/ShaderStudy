using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class EmissionRenderFeature : ScriptableRendererFeature
{
    public class RenderPass : ScriptableRenderPass
    {
        public Material Material_ScreenBlit;
        public Material Material_TransparentBlit;

        public Material Material_HBlur;
        public Material Material_VBlur;

        private class EmissionPassData
        {
            public TextureHandle EmissionBufferHnd;
            public TextureHandle EmissionDepthBufferHnd;
            public TextureHandle CameraDepthHnd;
            public RendererListHandle RendererListHnd;
        }
        private class EmissionBuffer2CameraBlitPassData
        {
            public Material Material_TransparentBlit;

            public TextureHandle EmissionBufferHnd;
        }
        private class BloomBlitPassData
        {
            public TextureHandle EmissionBufferHnd;
            public TextureHandle BloomTextureHnd0;
        }
        private class BlitPassData
        {
            public Material Material;

            public TextureHandle DepthBufferHnd;
            public TextureHandle SrcTextureHnd;
            public TextureHandle DstTextureHnd;
        }

        private void RecordBlitPass(RenderGraph renderGraph, string passName, Material material, TextureHandle srcTextureHnd, TextureHandle dstTextureHnd, TextureHandle depthTextureHnd)
        {
            using (var grphBuilder = renderGraph.AddRasterRenderPass<BlitPassData>(passName, out var passData))
            {
                passData.SrcTextureHnd = srcTextureHnd;
                passData.DstTextureHnd = dstTextureHnd;
                passData.DepthBufferHnd = depthTextureHnd;
                passData.Material = material;

                grphBuilder.UseTexture(in passData.SrcTextureHnd);
                grphBuilder.UseTexture(in passData.DepthBufferHnd);
                grphBuilder.SetRenderAttachment(passData.DstTextureHnd, 0);
                grphBuilder.SetRenderFunc(static (BlitPassData passData, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1.0f, 1.0f, 0, 0),
                        passData.Material, 0
                    );
                });
            }
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer context)
        {
            var frameData = context.Get<UniversalResourceData>();
            var renderingData = context.Get<UniversalRenderingData>();
            var cameraData = context.Get<UniversalCameraData>();


            var cameraColorDescriptor = frameData.cameraColor.GetDescriptor(renderGraph);
            var emissionBufferHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(cameraColorDescriptor.width, cameraColorDescriptor.height),
                "EmissionBuffer",
                true,
                FilterMode.Trilinear
            );
            var emissionDepthBufferHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(cameraColorDescriptor.width, cameraColorDescriptor.height, RenderTextureFormat.Depth, 16),
                "EmissionDepthBuffer",
                true,
                FilterMode.Trilinear
            );
            var grabTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(cameraColorDescriptor.width, cameraColorDescriptor.height),
                "GrabbedTexture",
                true,
                FilterMode.Trilinear
            );

            var bloomTexDownscaleDenominator = 2;
            var bloomTexWidth = cameraColorDescriptor.width / bloomTexDownscaleDenominator;
            var bloomTexHeight = cameraColorDescriptor.height / bloomTexDownscaleDenominator;

            // Downscale blit
            var bloomTextureHnd0 = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(bloomTexWidth, bloomTexHeight),
                "BloomTexture0",
                true,
                FilterMode.Trilinear
            );
            var bloomTextureHnd1 = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(bloomTexWidth, bloomTexHeight),
                "BloomTexture1",
                true,
                FilterMode.Trilinear
            );

            var drawSettings = new DrawingSettings(
                new ShaderTagId("Emission"),
                new SortingSettings(cameraData.camera)
                {
                    criteria = SortingCriteria.CommonOpaque
                }
            );
            var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
            var rendererList = renderGraph.CreateRendererList(new RendererListParams(renderingData.cullResults, drawSettings, filteringSettings));

            // Render emissions
            using (var grphBuilder = renderGraph.AddRasterRenderPass<EmissionPassData>("Emissions", out var passData))
            {
                passData.EmissionBufferHnd = emissionBufferHnd;
                passData.EmissionDepthBufferHnd = emissionDepthBufferHnd;
                passData.RendererListHnd = rendererList;
                passData.CameraDepthHnd = frameData.cameraDepth;

                grphBuilder.UseRendererList(passData.RendererListHnd); // Get Renderers
                grphBuilder.UseTexture(passData.CameraDepthHnd); // Use CameraDepth
                grphBuilder.SetRenderAttachment(emissionBufferHnd, 0); // Set Render Target
                grphBuilder.SetRenderAttachmentDepth(passData.EmissionDepthBufferHnd, AccessFlags.Write);
                grphBuilder.SetRenderFunc(static (EmissionPassData passData, RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(passData.RendererListHnd);
                });
                grphBuilder.SetGlobalTextureAfterPass(emissionDepthBufferHnd, Shader.PropertyToID("_EmissionDepthTexture"));

                grphBuilder.AllowPassCulling(false);
            }

            // Blit emissions to Camera
            using (var grphBuilder = renderGraph.AddRasterRenderPass<EmissionBuffer2CameraBlitPassData>("Emission_Blit", out var passData))
            {
                passData.EmissionBufferHnd = emissionBufferHnd;
                passData.Material_TransparentBlit = Material_TransparentBlit;

                grphBuilder.UseTexture(in passData.EmissionBufferHnd);
                grphBuilder.SetRenderAttachment(frameData.cameraColor, 0);
                grphBuilder.SetRenderFunc(static (EmissionBuffer2CameraBlitPassData passData, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.EmissionBufferHnd,
                        new Vector4(1.0f, 1.0f, 0, 0),
                        passData.Material_TransparentBlit, 0
                    );
                });
            }

            // Blit emission core color to Blur pass.
            using (var grphBuilder = renderGraph.AddRasterRenderPass<BloomBlitPassData>("Emission_BlitToBloom", out var passData))
            {
                passData.EmissionBufferHnd = emissionBufferHnd;
                passData.BloomTextureHnd0 = bloomTextureHnd0;

                grphBuilder.UseTexture(in passData.EmissionBufferHnd);
                grphBuilder.SetRenderAttachment(passData.BloomTextureHnd0, 0);
                grphBuilder.SetRenderFunc(static (BloomBlitPassData passData, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.EmissionBufferHnd,
                        new Vector4(1.0f, 1.0f, 0, 0),
                        0, true
                    );
                });
            }

            // Apply Blur
            RecordBlitPass(renderGraph, "EmissionBloom_HBlur", Material_HBlur, bloomTextureHnd0, bloomTextureHnd1, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_HBlur", Material_HBlur, bloomTextureHnd1, bloomTextureHnd0, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_HBlur", Material_HBlur, bloomTextureHnd0, bloomTextureHnd1, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_HBlur", Material_HBlur, bloomTextureHnd1, bloomTextureHnd0, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_VBlur", Material_VBlur, bloomTextureHnd0, bloomTextureHnd1, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_VBlur", Material_VBlur, bloomTextureHnd1, bloomTextureHnd0, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_VBlur", Material_VBlur, bloomTextureHnd0, bloomTextureHnd1, emissionDepthBufferHnd);
            RecordBlitPass(renderGraph, "EmissionBloom_VBlur", Material_VBlur, bloomTextureHnd1, bloomTextureHnd0, emissionDepthBufferHnd);

            RecordBlitPass(renderGraph, "EmissionBloom_ScreenBlit", Material_ScreenBlit, bloomTextureHnd0, frameData.cameraColor, emissionDepthBufferHnd);
        }
    }

    private RenderPass renderPass;

    public Material Material_ScreenBlit;
    public Material Material_TransparentBlit;
    public Material Material_HBlur;
    public Material Material_VBlur;

    public override void Create()
    {
        renderPass = new RenderPass
        {
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques,
            Material_ScreenBlit = Material_ScreenBlit,
            Material_TransparentBlit = Material_TransparentBlit,
            Material_HBlur = Material_HBlur,
            Material_VBlur = Material_VBlur,
        };
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
}