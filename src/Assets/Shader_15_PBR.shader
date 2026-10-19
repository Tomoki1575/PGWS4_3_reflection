Shader "Custom/Shader_15_PBR"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.86, 0.39, 0.39, 1)
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _Emission("Emission", Color) = (0,0,0,0)
        _Fresnel0("Fresnel0", Range(0,1)) = 0.8
        _Roughness("Roughness", Range(0,1)) = 0.4
        _Metallic("Metallic", Range(0,1)) = 0.6
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
                half4 _SpecularColor;
                half4 _Emission;
                half _Fresnel0;
                half _Roughness;
                half _Metallic;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.normal = TransformObjectToWorldNormal(IN.normal);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.position = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

            // 誘電体（金属以外）のフレネル反射率を、近似なしで計算する
            // co  : cosθ（視線とハーフベクトルの内積など）
            // f0  : 正面から見たときの反射率
            // f90 : 真横から見たときの反射率（通常は 1）
            half FresnelReflectanceAverageDielectric(float co, float f0, float f90)
            {
                // 0 や 1 ぴったりだと割り算・平方根が壊れるので、少し内側に収める
                co = min(0.9999, max(0.000001, co));

                // f0 と f90 から屈折率 n を逆算する
                float root_f0 = sqrt(f0);
                float root_f90 = sqrt(f90);
                float n = (root_f90 + root_f0) / (root_f90 - root_f0);
                float n2 = n * n;

                // sin²θ を求める（sin² + cos² = 1 より）
                float si2 = 1 - co * co;
                // スネルの法則から、屈折後の角度に関係する値を求める
                float nb = sqrt(n2 - si2);   // n × cos(屈折角)
                float bn = nb / n2;          // cos(屈折角) / n

                // 2種類の偏光それぞれの反射の強さ（振幅）
                float r_s = (co - nb) / (co + nb);   // s 偏光
                float r_p = (co - bn) / (co + bn);   // p 偏光
                // 2乗して反射率にし、2種類の平均を取る（自然光は半分ずつ混ざっているため）
                return 0.5 * f90 * (r_s * r_s + r_p * r_p);
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

            float V_SmithGGXCorrelated(float NdotL, float NdotV, float alphaG2)
            {
                float Lambda_GGXV = NdotL * sqrt((-NdotV * alphaG2 + NdotV) * NdotV + alphaG2);
                float Lambda_GGXL = NdotV * sqrt((-NdotL * alphaG2 + NdotL) * NdotL + alphaG2);
                return 0.5f / (Lambda_GGXL + Lambda_GGXV);

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

                half alpha = _Roughness * _Roughness;
                half3 diffuse = Fr_DisneyDiffuse(_BaseColor.rgb, LdotN, VdotN, LdotH, alpha) / PI;

                half alpha2 = alpha * alpha;
                float denom = HdotN * HdotN * (alpha2 - 1.0) + 1.0;
                float D = alpha2 / (PI * denom * denom);

                half G = min(1, 1 / (VdotN + sqrt(alpha2 + (1.0 - alpha2) * VdotN * VdotN)) / (LdotN + sqrt(alpha2 + (1.0 - alpha2) * LdotN * LdotN)));

                half F = _Fresnel0 + (1 - _Fresnel0) * pow(1 - VdotH,5);

                half3 brdf = _BaseColor * D * G * F / (4 * LdotN * VdotN);

                half3 color = light.color * LdotN * lerp(diffuse, brdf, _Metallic);
                color += _Emission;
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
