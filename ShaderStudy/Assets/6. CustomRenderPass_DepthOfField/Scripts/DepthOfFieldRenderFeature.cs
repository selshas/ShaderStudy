using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEditor.Search;

public class DepthOfFieldRenderFeature : ScriptableRendererFeature
{
    public class RenderPass : ScriptableRenderPass
    {
        private class GrabPassData
        {
            public Material Material;
            public TextureHandle SrcTextureHnd;
            public TextureHandle DstTextureHnd;
        }
        private class BlitPassData
        {
            public Material Material;
            public TextureHandle SrcTextureHnd;
            public TextureHandle SrcDepthTextureHnd;
            public TextureHandle DstTextureHnd;

            public float BlurIntensity;
            public float FocalRange;
            public float FocalDistance;
            public DOFDisplayMode DisplayMode;
        }
        private class CompositePassData
        {
            public Material Material;
            public TextureHandle SharpTextureHnd;
            public TextureHandle BlurredTextureHnd;
            public TextureHandle DstTextureHnd;

            public float FocalDistance;
            public float FocalRange;
            public bool EnablePostFilter;
            public DOFDisplayMode DisplayMode;
        }

        public Material Material_DOFBlit;
        public float BlurIntensity;
        public float FocalRange;
        public float FocalDistance;
        public DOFDisplayMode DisplayMode;
        public bool EnablePostFilter;

        private void RecordBlurPass(RenderGraph renderGraph, TextureHandle srcTextureHnd, TextureHandle srcDepthTextureHnd, TextureHandle dstTextureHnd)
        {
            using (var grphBuilder = renderGraph.AddRasterRenderPass<BlitPassData>("DoFApplyingBlit", out var passData))
            {
                passData.Material = Material_DOFBlit;
                passData.SrcTextureHnd = srcTextureHnd;
                passData.SrcDepthTextureHnd = srcDepthTextureHnd;
                passData.DstTextureHnd = dstTextureHnd;
                passData.BlurIntensity = BlurIntensity;
                passData.FocalDistance = FocalDistance;
                passData.FocalRange = FocalRange;
                passData.DisplayMode = DisplayMode;

                grphBuilder.UseTexture(passData.SrcTextureHnd, AccessFlags.ReadWrite);
                grphBuilder.UseTexture(passData.SrcDepthTextureHnd);
                grphBuilder.SetRenderAttachment(passData.DstTextureHnd, 0);
                grphBuilder.SetRenderFunc<BlitPassData>(static (passData, context) =>
                {
                    passData.Material.SetTexture("_DepthTexture", passData.SrcDepthTextureHnd);
                    passData.Material.SetFloat("_BlurIntensity", passData.BlurIntensity);
                    passData.Material.SetFloat("_FocalDistance", passData.FocalDistance);
                    passData.Material.SetFloat("_FocalRange", passData.FocalRange);
                    passData.Material.SetInt("_DbgDisplayMode", (int)passData.DisplayMode);
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 1
                    );
                });
            }
        }
        private void RecordCompositePass(RenderGraph renderGraph, TextureHandle sharpTextureHnd, TextureHandle blurredTextureHnd, TextureHandle dstTextureHnd)
        {
            using (var grphBuilder = renderGraph.AddRasterRenderPass<CompositePassData>("DoFComposition", out var passData))
            {
                passData.SharpTextureHnd = sharpTextureHnd;
                passData.BlurredTextureHnd = blurredTextureHnd;
                passData.DstTextureHnd = dstTextureHnd;
                passData.Material = Material_DOFBlit;
                passData.FocalDistance = FocalDistance;
                passData.FocalRange = FocalRange;
                passData.EnablePostFilter = EnablePostFilter;
                passData.DisplayMode = DisplayMode;

                grphBuilder.UseTexture(passData.SharpTextureHnd);
                grphBuilder.UseTexture(passData.BlurredTextureHnd);
                grphBuilder.SetRenderAttachment(passData.DstTextureHnd, 0);
                grphBuilder.SetRenderFunc<CompositePassData>((passData, context) =>
                {
                    passData.Material.SetTexture("_BlurredTexture", passData.BlurredTextureHnd);
                    passData.Material.SetFloat("_FocalDistance", passData.FocalDistance);
                    passData.Material.SetFloat("_FocalRange", passData.FocalRange);
                    passData.Material.SetInt("_EnablePostFilter", passData.EnablePostFilter ? 1 : 0);
                    passData.Material.SetInt("_DbgDisplayMode", (int)passData.DisplayMode);

                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SharpTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 2
                    );
                });
            }
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            var camColorDesc = resourceData.cameraColor.GetDescriptor(renderGraph);

            var cameraGrabTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width, camColorDesc.height, RenderTextureFormat.DefaultHDR), "CameraGrab",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );
            var blurredTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width / 2, camColorDesc.height / 2, RenderTextureFormat.DefaultHDR), "Result",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );

            using (var grphBuilder = renderGraph.AddRasterRenderPass<GrabPassData>("DoFCameraGrab", out var passData))
            {
                passData.SrcTextureHnd = resourceData.cameraColor;
                passData.DstTextureHnd = cameraGrabTextureHnd;
                passData.Material = Material_DOFBlit;

                grphBuilder.UseTexture(passData.SrcTextureHnd);
                grphBuilder.SetRenderAttachment(cameraGrabTextureHnd, 0);
                grphBuilder.SetRenderFunc<GrabPassData>((passData, context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 0
                    );
                });
            }

            RecordBlurPass(renderGraph, cameraGrabTextureHnd, resourceData.activeDepthTexture, blurredTextureHnd);
            RecordCompositePass(renderGraph, cameraGrabTextureHnd, blurredTextureHnd, resourceData.cameraColor);
        }
    }

    public enum DOFDisplayMode
    { 
        Blended = 0,
        COCVisualization = 1,
        Foreground = 2,
        Background = 3
    }

    private RenderPass renderPass;

    public Material Material_DOFBlit;
    [Range(0, 1)]
    public float BlurIntensity = 0.1f;
    [Range(0, 100)]
    public float FocalRange = 10f;
    [Range(0, 100)]
    public float FocusDistance = 10f;
    public DOFDisplayMode DisplayMode = DOFDisplayMode.Blended;
    public bool EnablePostFilter = true;

    public override void Create()
    {
        renderPass = new RenderPass() {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
            Material_DOFBlit = Material_DOFBlit,
            BlurIntensity = BlurIntensity,
            FocalDistance = FocusDistance,
            FocalRange = FocalRange,
            DisplayMode = DisplayMode,
            EnablePostFilter = EnablePostFilter,
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
}
