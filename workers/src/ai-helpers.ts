// Helper functions to add to ai.ts

async function callGemini(prompt: string, apiKey: string, model: string): Promise<string> {
    const GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models';

    const response = await fetch(`${GEMINI_API_URL}/${model}:generateContent?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.7, maxOutputTokens: 2048 },
            safetySettings: [
                { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
                { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_NONE' },
                { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_NONE' },
                { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_NONE' },
            ],
        }),
    });

    if (!response.ok) {
        const error = await response.text();
        console.error('Gemini API Error:', error);
        throw new Error(`Gemini API error: ${response.status} - ${error}`);
    }

    const data = await response.json() as any;
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!text) {
        throw new Error('No content in Gemini response');
    }

    return text;
}

async function callOpenRouter(prompt: string, apiKey: string, model: string): Promise<string> {
    const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions';

    const response = await fetch(OPENROUTER_API_URL, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
            'HTTP-Referer': 'https://monitorwatch.app',
            'X-Title': 'MonitorWatch',
        },
        body: JSON.stringify({
            model: model,
            messages: [
                { role: 'user', content: prompt }
            ],
            temperature: 0.7,
            max_tokens: 2048,
        }),
    });

    if (!response.ok) {
        const error = await response.text();
        console.error('OpenRouter API Error:', error);
        throw new Error(`OpenRouter API error: ${response.status} - ${error}`);
    }

    const data = await response.json() as any;
    const text = data.choices?.[0]?.message?.content;

    if (!text) {
        throw new Error('No content in OpenRouter response');
    }

    return text;
}
