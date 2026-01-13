/**
 * Vision/OCR Handler - OpenRouter
 */

import { Env } from '../types';

export async function handleVision(
    request: Request,
    userId: string,
    env: Env
): Promise<Response> {
    try {
        const { image, model, prompt } = await request.json() as {
            image: string;
            model?: string;
            prompt?: string;
        };

        if (!image) {
            return new Response(JSON.stringify({ error: 'No image provided' }), {
                status: 400,
                headers: { 'Content-Type': 'application/json' }
            });
        }

        // Get OpenRouter key from user config
        const aiConfigRaw = await env.CONFIG.get(`ai_config:${userId}`);
        if (!aiConfigRaw) {
            return new Response(JSON.stringify({ error: 'AI config not found' }), {
                status: 400,
                headers: { 'Content-Type': 'application/json' }
            });
        }

        const aiConfig = JSON.parse(aiConfigRaw);
        const openRouterKey = aiConfig.openRouterKey;

        if (!openRouterKey) {
            return new Response(JSON.stringify({ error: 'OpenRouter API key not configured' }), {
                status: 400,
                headers: { 'Content-Type': 'application/json' }
            });
        }

        const visionModel = model || 'gpt-4o';
        const visionPrompt = prompt || 'Extract all visible text from this image. Return only the text, no commentary.';

        // Analyze image via OpenRouter
        const result = await analyzeImage(image, visionModel, visionPrompt, openRouterKey);

        return new Response(JSON.stringify({ text: result }), {
            headers: { 'Content-Type': 'application/json' }
        });
    } catch (error) {
        console.error('Vision error:', error);
        return new Response(JSON.stringify({ error: 'Vision analysis failed', details: String(error) }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

async function analyzeImage(imageBase64: string, model: string, prompt: string, apiKey: string): Promise<string> {
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://monitorwatch.app',
            'X-Title': 'MonitorWatch'
        },
        body: JSON.stringify({
            model: model,
            messages: [{
                role: 'user',
                content: [
                    { type: 'text', text: prompt },
                    {
                        type: 'image_url',
                        image_url: {
                            url: imageBase64.startsWith('data:')
                                ? imageBase64
                                : `data:image/jpeg;base64,${imageBase64}`
                        }
                    }
                ]
            }],
            max_tokens: 1000
        })
    });

    if (!response.ok) {
        const error = await response.text();
        throw new Error(`OpenRouter API error: ${response.status} - ${error}`);
    }

    const data = await response.json() as any;
    return data.choices[0].message.content;
}
