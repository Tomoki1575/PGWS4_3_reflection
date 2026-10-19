Shader "Custom/Shader_14_FrostbiteDiffuse"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.86, 0.39, 0.39, 1)
        _Fresnel0("Fresnel0", Range(0,1)) = 0.8
        _Roughness("Roughness", Range(0,1)) = 0.4
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 position : TEXCOORD1;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half _Fresnel0;
                half _Roughness;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.normal = TransformObjectToWorldNormal(IN.normal);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.position = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

            half Fresnel(half f0, half f90, float co)
            {
                return f0 + (f90 - f0) * pow(1 - co, 5);
            }

            half3 Fr_DisneyDiffuse(half3 albedo, half LdotN, half VdotN, half LdotH, half linearRoughness)
            {
                // ディズニーのモデルにおけるフレネル反射の強さを定義
                float energyBias = lerp(0.0, 0.5, linearRoughness);
                float energyFactor = lerp(1.0, 1.0 / 1.51, linearRoughness);
    
                // エッジ部分での視野角・ライト角に応じたフレネル項の計算
                float Fd90 = energyBias + 2.0 * LdotH * LdotH * linearRoughness;
    
                // Schlickの近似を用いたフレネルの計算
                float lightScatter = Fresnel(1, Fd90, LdotN);
                float viewScatter  = Fresnel(1, Fd90, VdotN);

                // 最終的な拡散反射率の係数を出力（πで割る前の値、あるいはπを含めるかはエンジンによる）
                return (albedo * lightScatter * viewScatter * energyFactor);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                Light light = GetMainLight();
                half3 normal = normalize(IN.normal);
                half3 view_direction = normalize(TransformViewToWorld(float3(0,0,0)) - IN.position);
                half3 half_vector = normalize(light.direction + view_direction);
                
                
                half VdotN = max(0.0001, dot(view_direction, normal));
                half LdotN = max(0.0001, dot(light.direction,normal));
                half HdotN = max(0.0001, dot(half_vector, normal));

                half LdotH = max(0, dot(half_vector, light.direction));
                half VdotH = max(0, dot(half_vector, view_direction));

                half alpha2 = _Roughness * _Roughness * _Roughness * _Roughness;
                float denom = HdotN * HdotN * (alpha2 - 1.0) + 1.0;
                float D = alpha2 / (PI * denom * denom);

                half G = min(1, 1 / (VdotN + sqrt(alpha2 + (1.0 - alpha2) * VdotN * VdotN)) / (LdotN + sqrt(alpha2 + (1.0 - alpha2) * LdotN * LdotN)));

                half F = _Fresnel0 + (1 - _Fresnel0) * pow(1 - VdotH,5);

                half3 brdf = _BaseColor * D * G * F / (4 * LdotN * VdotN);

                half3 color = light.color * LdotN * Fr_DisneyDiffuse(_BaseColor, LdotN, VdotN, LdotH, _Roughness * _Roughness) / PI;
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
