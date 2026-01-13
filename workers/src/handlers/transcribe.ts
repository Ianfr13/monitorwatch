/**
 * Audio Transcription Handler - OpenRouter
 * 
 * IMPORTANT: This handler processes audio files and returns text.
 * Files are NOT stored - they are processed and immediately discarded.
 * Only the transcribed text is saved to the database.
 */

import { Env } from '../types';

export async function handleTranscribe(
    request: Request,
    userId: string,
    env: Env
): Promise<Response> {
    try {
        const formData = await request.formData();
        const audioFile = formData.get('file') as unknown as File;
        const model = formData.get('model') as string || 'whisper-1';

        if (!audioFile) {
            return new Response(JSON.stringify({ error: 'No audio file provided' }), {
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

        // Forward to OpenRouter
        const transcription = await transcribeAudio(audioFile, model, openRouterKey);

        return new Response(JSON.stringify({ text: transcription }), {
            headers: { 'Content-Type': 'application/json' }
        });
    } catch (error) {
        console.error('Transcription error:', error);
        return new Response(JSON.stringify({ error: 'Transcription failed', details: String(error) }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

async function transcribeAudio(file: File, model: string, apiKey: string): Promise<string> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('model', model);

    const response = await fetch('https://openrouter.ai/api/v1/audio/transcriptions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${apiKey}`,
            'HTTP-Referer': 'https://monitorwatch.app',
            'X-Title': 'MonitorWatch'
        },
        body: formData
    });

    if (!response.ok) {
        const error = await response.text();
        throw new Error(`OpenRouter API error: ${response.status} - ${error}`);
    }

    const data = await response.json() as { text: string };
    return data.text;
}
