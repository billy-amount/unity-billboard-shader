Shader "Custom/SimpleBillboardWebGL"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
        _Cutoff ("Cutoff", Range(0,1)) = 0.5
        _Scale ("Scale", Float) = 1.0
    }
    SubShader
    {
        Tags
        {
            "RenderType"="TransparentCutout"
            "Queue"="AlphaTest"
            "RenderPipeline"="UniversalPipeline" // критично: без этого тега URP не увидит шейдер
            "IgnoreProjector"="True"
        }
        Cull Off
        ZWrite On

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" } // URP-аналог ForwardBase

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            // поддержка доп. источников света (фонарей), per-vertex или per-pixel
            // в зависимости от настроек URP Asset -> Lighting -> Additional Lights
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _FORWARD_PLUS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 diffuse : TEXCOORD1;
                float fogCoord : TEXCOORD2;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            // CBUFFER об€зателен именно в таком виде дл€ совместимости со SRP Batcher Ч
            // это ещЄ один бонус к производительности, который в URP доступен "бесплатно"
            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float _Cutoff;
                float _Scale;
            CBUFFER_END

            Varyings vert (Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                // ѕростой billboard (логика та же, что и раньше)
                float3 worldPos = TransformObjectToWorld(float3(0, 0, 0));
                float3 viewDir = GetCameraPositionWS() - worldPos;
                viewDir.y = 0;
                viewDir = normalize(viewDir);

                float3 right = normalize(cross(float3(0, 1, 0), viewDir));

                float3 local = v.positionOS.xyz * _Scale;
                float3 billboard = right * local.x + float3(0, 1, 0) * local.y;
                float3 worldVertPos = worldPos + billboard;

                o.positionCS = TransformWorldToHClip(worldVertPos);
                o.uv = v.uv;

                // ѕсевдо-нормаль billboard'а Ч смотрит на камеру
                float3 normalWS = viewDir;

                // 1) Ambient / Light Probes Ч реагирует на Environment Lighting
                float3 lighting = SampleSH(normalWS);

                // 2) ќсновной directional light сцены (если по€витс€)
                Light mainLight = GetMainLight();
                float ndotl = dot(normalWS, mainLight.direction) * 0.5 + 0.5;
                lighting += mainLight.color * ndotl;

                // 3) ƒополнительные источники (уличные фонари), считаем per-vertex Ч
                //    дЄшево дл€ WebGL при большом количестве билбордов
                #if defined(_ADDITIONAL_LIGHTS) || defined(_ADDITIONAL_LIGHTS_VERTEX)
                uint additionalLightsCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < additionalLightsCount; i++)
                {
                    Light light = GetAdditionalLight(i, worldVertPos);
                    float ndotlAdd = saturate(dot(normalWS, light.direction) * 0.5 + 0.5);
                    lighting += light.color * light.distanceAttenuation * ndotlAdd;
                }
                #endif

                o.diffuse = lighting;
                o.fogCoord = ComputeFogFactor(o.positionCS.z);

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _Color;
                col.rgb *= i.diffuse;

                clip(col.a - _Cutoff);

                col.rgb = MixFog(col.rgb, i.fogCoord);
                return col;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
