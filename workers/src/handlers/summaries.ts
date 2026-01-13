import { Env, Activity, Transcript } from '../types';
import { generateId } from '../utils';

// Summarize a chunk of activities/transcripts
async function summarizeChunk(
    activities: Activity[],
    transcripts: Transcript[],
    apiKey: string,
    model: string,
    language: string
): Promise<string> {
    if (activities.length === 0 && transcripts.length === 0) {
        return '';
    }

    // Extract content
    const titles = [...new Set(activities.map(a => a.window_title).filter(Boolean))];
    const ocrContent = activities.map(a => a.ocr_text).filter(Boolean).join('\n');
    const transcriptText = transcripts.map(t => t.text).filter(Boolean).join('\n');

    const prompt = language === 'pt' 
        ? buildPortugueseChunkPrompt(titles, ocrContent, transcriptText)
        : buildEnglishChunkPrompt(titles, ocrContent, transcriptText);

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            model,
            messages: [{ role: 'user', content: prompt }],
            temperature: 0.5,
            max_tokens: 1024,
        }),
    });

    if (!response.ok) {
        throw new Error(`OpenRouter error: ${response.status}`);
    }

    const data = await response.json() as any;
    return data.choices?.[0]?.message?.content || '';
}

function buildEnglishChunkPrompt(titles: string[], ocrContent: string, transcripts: string): string {
    return `Analyze this 30-minute activity chunk and extract key information.

## Window Titles
${titles.join('\n') || 'None'}

## Screen Content (Note: May contain OCR errors - interpret intelligently)
${ocrContent || 'None'}

## Audio/Conversations
${transcripts || 'None'}

---

Extract and summarize in 2-3 paragraphs:
- What was being worked on or studied
- Key topics, projects, or tasks
- Important details, decisions, or learnings
- Any conversations or meetings

IMPORTANT: The screen content may have OCR errors. Fix obvious mistakes:
- "WhitsApp" → "WhatsApp"
- "Antigr4vity" → "Antigravity"  
- "Wi$pr" → "Whisper"
- "Tennlno1" → "Terminal"
- "Xrodg" → "Xcode"
- Numbers/symbols in place of letters are OCR errors

Be specific and detailed. Use CORRECT app/tool names.
Output only the summary, no headers or formatting.`;
}

function buildPortugueseChunkPrompt(titles: string[], ocrContent: string, transcripts: string): string {
    return `Analise este chunk de 30 minutos de atividade e extraia informacoes chave.

## Titulos das Janelas
${titles.join('\n') || 'Nenhum'}

## Conteudo da Tela (Nota: Pode conter erros de OCR - interprete inteligentemente)
${ocrContent || 'Nenhum'}

## Audio/Conversas
${transcripts || 'Nenhum'}

---

Extraia e resuma em 2-3 paragrafos:
- O que estava sendo trabalhado ou estudado
- Topicos principais, projetos ou tarefas
- Detalhes importantes, decisoes ou aprendizados
- Conversas ou reunioes

IMPORTANTE: O conteudo da tela pode ter erros de OCR. Corrija erros obvios:
- "WhitsApp" → "WhatsApp"
- "Antigr4vity" → "Antigravity"
- "Wi$pr" → "Whisper"
- "Tennlno1" → "Terminal"
- "Xrodg" → "Xcode"
- Numeros/simbolos no lugar de letras sao erros de OCR

Seja especifico e detalhado. Use nomes CORRETOS de apps/ferramentas.
Retorne apenas o resumo, sem cabecalhos ou formatacao.`;
}

// Process a specific hour: get activities, split into 2 chunks of 30min, summarize
export async function processHourlySummary(
    userId: string,
    date: string,
    hour: number,
    env: Env,
    apiKey: string,
    model: string = 'google/gemini-2.0-flash-001',
    language: string = 'en'
): Promise<string> {
    // Check if already processed
    const existing = await env.DB.prepare(`
        SELECT summary FROM hourly_summaries WHERE user_id = ? AND date = ? AND hour = ?
    `).bind(userId, date, hour).first() as { summary: string } | null;

    if (existing?.summary) {
        return existing.summary;
    }

    // Get activities for this hour
    const hourStart = `${date}T${hour.toString().padStart(2, '0')}:00:00`;
    const hourEnd = `${date}T${hour.toString().padStart(2, '0')}:59:59`;
    const midPoint = `${date}T${hour.toString().padStart(2, '0')}:30:00`;

    const activitiesResult = await env.DB.prepare(`
        SELECT * FROM activities 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, hourStart, hourEnd).all();
    const activities = (activitiesResult.results || []) as unknown as Activity[];

    const transcriptsResult = await env.DB.prepare(`
        SELECT * FROM transcripts 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, hourStart, hourEnd).all();
    const transcripts = (transcriptsResult.results || []) as unknown as Transcript[];

    if (activities.length === 0 && transcripts.length === 0) {
        return '';
    }

    // Split into 2 chunks of 30min
    const chunk1Activities = activities.filter(a => a.timestamp < midPoint);
    const chunk2Activities = activities.filter(a => a.timestamp >= midPoint);
    const chunk1Transcripts = transcripts.filter(t => t.timestamp < midPoint);
    const chunk2Transcripts = transcripts.filter(t => t.timestamp >= midPoint);

    // Summarize each chunk
    const summaries: string[] = [];
    
    if (chunk1Activities.length > 0 || chunk1Transcripts.length > 0) {
        const summary1 = await summarizeChunk(chunk1Activities, chunk1Transcripts, apiKey, model, language);
        if (summary1) summaries.push(summary1);
    }
    
    if (chunk2Activities.length > 0 || chunk2Transcripts.length > 0) {
        const summary2 = await summarizeChunk(chunk2Activities, chunk2Transcripts, apiKey, model, language);
        if (summary2) summaries.push(summary2);
    }

    const combinedSummary = summaries.join('\n\n');

    // Save to database
    if (combinedSummary) {
        const id = generateId();
        await env.DB.prepare(`
            INSERT INTO hourly_summaries (id, user_id, date, hour, summary)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id, date, hour) DO UPDATE SET
                summary = excluded.summary
        `).bind(id, userId, date, hour, combinedSummary).run();
    }

    return combinedSummary;
}

// Get all hourly summaries for a date
export async function getHourlySummaries(
    userId: string,
    date: string,
    env: Env
): Promise<{ hour: number; summary: string }[]> {
    const result = await env.DB.prepare(`
        SELECT hour, summary FROM hourly_summaries 
        WHERE user_id = ? AND date = ?
        ORDER BY hour ASC
    `).bind(userId, date).all();

    return (result.results || []) as { hour: number; summary: string }[];
}

// Process all hours with data for a date (called by cron or on-demand)
export async function processAllHoursForDate(
    userId: string,
    date: string,
    env: Env,
    apiKey: string,
    model: string = 'google/gemini-2.0-flash-001',
    language: string = 'en'
): Promise<number> {
    // Find which hours have data
    const hoursResult = await env.DB.prepare(`
        SELECT DISTINCT CAST(strftime('%H', timestamp) AS INTEGER) as hour
        FROM activities 
        WHERE user_id = ? AND date(timestamp) = ?
        ORDER BY hour
    `).bind(userId, date).all();

    const hours = (hoursResult.results || []).map((r: any) => r.hour as number);
    let processed = 0;

    for (const hour of hours) {
        // Check if already processed
        const existing = await env.DB.prepare(`
            SELECT id FROM hourly_summaries WHERE user_id = ? AND date = ? AND hour = ?
        `).bind(userId, date, hour).first();

        if (!existing) {
            await processHourlySummary(userId, date, hour, env, apiKey, model, language);
            processed++;
        }
    }

    return processed;
}

// Generate a standalone hour note with WikiLinks
export async function generateHourNote(
    userId: string,
    date: string,
    hour: number,
    vaultNotes: string[],
    env: Env,
    apiKey: string,
    model: string = 'google/gemini-2.0-flash-001',
    language: string = 'en'
): Promise<{ note: string; title: string }> {
    // Get activities for this hour
    const hourStart = `${date}T${hour.toString().padStart(2, '0')}:00:00`;
    const hourEnd = `${date}T${hour.toString().padStart(2, '0')}:59:59`;

    const activitiesResult = await env.DB.prepare(`
        SELECT * FROM activities 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, hourStart, hourEnd).all();
    const activities = (activitiesResult.results || []) as unknown as Activity[];

    const transcriptsResult = await env.DB.prepare(`
        SELECT * FROM transcripts 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, hourStart, hourEnd).all();
    const transcripts = (transcriptsResult.results || []) as unknown as Transcript[];

    if (activities.length === 0 && transcripts.length === 0) {
        return { note: '', title: '' };
    }

    // Extract content
    const titles = [...new Set(activities.map(a => a.window_title).filter(Boolean))];
    const ocrContent = activities.map(a => a.ocr_text).filter(Boolean).join('\n');
    const transcriptText = transcripts.map(t => t.text).filter(Boolean).join('\n');

    const prompt = language === 'pt'
        ? buildPortugueseHourNotePrompt(date, hour, titles, ocrContent, transcriptText, vaultNotes)
        : buildEnglishHourNotePrompt(date, hour, titles, ocrContent, transcriptText, vaultNotes);

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            model,
            messages: [{ role: 'user', content: prompt }],
            temperature: 0.7,
            max_tokens: 2048,
        }),
    });

    if (!response.ok) {
        throw new Error(`OpenRouter error: ${response.status}`);
    }

    const data = await response.json() as any;
    const note = data.choices?.[0]?.message?.content || '';
    
    // Extract title from the generated note (first H1)
    const titleMatch = note.match(/^#\s+(.+)$/m);
    let title = titleMatch ? titleMatch[1].trim() : '';
    
    // Clean title for filename
    title = title
        .replace(/[<>:"/\\|?*]/g, '') // Remove invalid filename chars
        .replace(/\s+/g, ' ')          // Normalize spaces
        .trim()
        .slice(0, 100);                // Limit length
    
    // Fallback title if extraction failed
    if (!title) {
        const hourStr = hour.toString().padStart(2, '0');
        title = language === 'pt' ? `Nota ${date} ${hourStr}h` : `Note ${date} ${hourStr}h`;
    }

    return { note, title };
}

function buildEnglishHourNotePrompt(
    date: string,
    hour: number,
    titles: string[],
    ocrContent: string,
    transcripts: string,
    vaultNotes: string[]
): string {
    const hourStr = `${hour.toString().padStart(2, '0')}:00`;
    const generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);
    const vaultNotesStr = vaultNotes.length > 0 
        ? vaultNotes.join(', ')
        : 'None available';

    return `Generate a concise hour note for ${date} at ${hourStr}.

## Activity Data

### Window Titles
${titles.join('\n') || 'None'}

### Screen Content
${ocrContent || 'None'}

### Audio/Conversations
${transcripts || 'None'}

## Existing Notes in Vault (for WikiLinks)
${vaultNotesStr}

---

## Instructions

Create a Markdown note with:

1. **Title (H1)**: A descriptive title based on the MAIN subject/topic of this hour. Examples:
   - "Refactoring CloudAPI Module"
   - "Meeting with Design Team"
   - "Studying React Hooks"
   - "Debugging Authentication Flow"
   The title should reflect what was predominantly done, NOT generic like "Hour Note".

2. **Subtitle**: Right after the title, add: *Generated: ${generatedAt}*

3. **Summary**: 2-3 paragraphs describing what was done during this hour

4. **WikiLinks**: Look at the existing notes list and create [[WikiLinks]] to relevant notes that connect to this hour's activities. Only link to notes that actually exist in the vault and are relevant.

5. **Tags**: Add relevant #tags based on the content

## Output Format Example
\`\`\`
# Implementing User Authentication

*Generated: ${generatedAt}*

Summary paragraphs here...

Related: [[Auth System]], [[Security Notes]]

#dev #authentication #backend
\`\`\`

## Rules
- ZERO EMOJIS
- Title must be descriptive of the main activity (NOT "Hour Note" or time-based)
- Be specific and detailed
- Only create WikiLinks to notes that exist in the vault list provided
- Output only the Markdown note, no conversation`;
}

function buildPortugueseHourNotePrompt(
    date: string,
    hour: number,
    titles: string[],
    ocrContent: string,
    transcripts: string,
    vaultNotes: string[]
): string {
    const hourStr = `${hour.toString().padStart(2, '0')}:00`;
    const generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);
    const vaultNotesStr = vaultNotes.length > 0 
        ? vaultNotes.join(', ')
        : 'Nenhuma disponivel';

    return `Gere uma nota de hora concisa para ${date} as ${hourStr}.

## Dados de Atividade

### Titulos das Janelas
${titles.join('\n') || 'Nenhum'}

### Conteudo da Tela
${ocrContent || 'Nenhum'}

### Audio/Conversas
${transcripts || 'Nenhum'}

## Notas Existentes no Vault (para WikiLinks)
${vaultNotesStr}

---

## Instrucoes

Crie uma nota Markdown com:

1. **Titulo (H1)**: Um titulo descritivo baseado no ASSUNTO PRINCIPAL desta hora. Exemplos:
   - "Refatorando Modulo CloudAPI"
   - "Reuniao com Time de Design"
   - "Estudando React Hooks"
   - "Debugando Fluxo de Autenticacao"
   O titulo deve refletir o que foi predominantemente feito, NAO generico como "Nota da Hora".

2. **Subtitulo**: Logo apos o titulo, adicione: *Gerado em: ${generatedAt}*

3. **Resumo**: 2-3 paragrafos descrevendo o que foi feito durante esta hora

4. **WikiLinks**: Olhe a lista de notas existentes e crie [[WikiLinks]] para notas relevantes que conectam com as atividades desta hora. Apenas linke para notas que realmente existem no vault e sao relevantes.

5. **Tags**: Adicione #tags relevantes baseadas no conteudo

## Formato de Saida Exemplo
\`\`\`
# Implementando Autenticacao de Usuario

*Gerado em: ${generatedAt}*

Paragrafos de resumo aqui...

Relacionado: [[Sistema Auth]], [[Notas de Seguranca]]

#dev #autenticacao #backend
\`\`\`

## Regras
- ZERO EMOJIS
- Titulo deve ser descritivo da atividade principal (NAO "Nota da Hora" ou baseado em horario)
- Seja especifico e detalhado
- Apenas crie WikiLinks para notas que existem na lista do vault fornecida
- Retorne apenas a nota Markdown, sem conversacao`;
}
