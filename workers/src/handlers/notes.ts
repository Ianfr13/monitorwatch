import { Env, GenerateNoteRequest, Note, Activity, Transcript } from '../types';
import { generateId, isValidDateString, isValidTimestamp, sanitizeString } from '../utils';
import { getActivitiesForDate } from './activity';
import { getTranscriptsForDate } from './transcript';
import { generateNoteWithAI, generateMeetingNoteWithAI } from '../ai';
import { getHourlySummaries, processAllHoursForDate } from './summaries';

// Helper to get AI config from request headers
function getAIConfigFromRequest(request: Request) {
    const openRouterKey = request.headers.get('X-OpenRouter-Key');
    const language = request.headers.get('X-Note-Language') || 'en';
    
    if (openRouterKey) {
        return {
            provider: 'openrouter',
            openRouterKey: openRouterKey,
            model: 'google/gemini-2.0-flash-001',
            language: language
        };
    }
    return undefined;
}

export async function handleGenerateNote(
    payload: GenerateNoteRequest,
    userId: string,
    env: Env,
    request: Request
): Promise<{ success: boolean; note: string; noteNumber: number }> {
    const { date } = payload;

    // Validate date format
    if (!date || !isValidDateString(date)) {
        throw new Error('Invalid date format. Expected YYYY-MM-DD');
    }

    // Get activities and transcripts for the date
    const activities = await getActivitiesForDate(date, userId, env);
    const transcripts = await getTranscriptsForDate(date, userId, env);

    if (activities.length === 0 && transcripts.length === 0) {
        return { success: false, note: '', noteNumber: 0 };
    }

    // Get AI config from request headers
    const aiConfig = getAIConfigFromRequest(request);
    
    if (!aiConfig?.openRouterKey) {
        throw new Error('OpenRouter API key not provided. Configure it in Settings.');
    }

    // Count existing notes for this date to get next note number
    const countResult = await env.DB.prepare(`
        SELECT COUNT(*) as count FROM notes WHERE user_id = ? AND date = ?
    `).bind(userId, date).first() as { count: number } | null;
    const noteNumber = (countResult?.count || 0) + 1;

    // Get pre-processed hourly summaries if available
    let hourlySummaries = await getHourlySummaries(userId, date, env);
    
    // If no summaries, process them now (slower but ensures data)
    if (hourlySummaries.length === 0 && aiConfig?.openRouterKey) {
        await processAllHoursForDate(userId, date, env, aiConfig.openRouterKey, aiConfig.model, aiConfig.language);
        hourlySummaries = await getHourlySummaries(userId, date, env);
    }

    // Generate note with AI using summaries or raw data
    const content = await generateNoteWithAI(activities, transcripts, date, env, aiConfig, noteNumber, hourlySummaries);

    // Insert new note with note_number
    const id = generateId();
    await env.DB.prepare(`
        INSERT INTO notes (id, user_id, date, note_number, content, version, updated_at)
        VALUES (?, ?, ?, ?, ?, 1, datetime('now'))
    `).bind(id, userId, date, noteNumber, content).run();

    return { success: true, note: content, noteNumber };
}

export async function handleGetNote(
    date: string,
    userId: string,
    env: Env
): Promise<{ note: Note | null }> {
    const note = await getNote(date, userId, env);
    return { note };
}

async function getNote(date: string, userId: string, env: Env): Promise<Note | null> {
    // Get the latest note for the date
    const result = await env.DB.prepare(`
        SELECT * FROM notes WHERE user_id = ? AND date = ?
        ORDER BY note_number DESC LIMIT 1
    `).bind(userId, date).first();

    return result as Note | null;
}

async function getNotesForDate(date: string, userId: string, env: Env): Promise<Note[]> {
    const result = await env.DB.prepare(`
        SELECT * FROM notes WHERE user_id = ? AND date = ?
        ORDER BY note_number ASC
    `).bind(userId, date).all();

    return (result.results || []) as unknown as Note[];
}

export async function handleGenerateMeetingNote(
    payload: { startTime: string; endTime: string; context: string },
    userId: string,
    env: Env,
    request: Request
): Promise<{ success: boolean; note: string; filename: string }> {
    const { startTime, endTime, context } = payload;

    // Validate timestamps
    if (!startTime || !isValidTimestamp(startTime)) {
        throw new Error('Invalid startTime format');
    }
    if (!endTime || !isValidTimestamp(endTime)) {
        throw new Error('Invalid endTime format');
    }
    
    // Validate time range (max 24 hours)
    const start = new Date(startTime);
    const end = new Date(endTime);
    if (end.getTime() - start.getTime() > 24 * 60 * 60 * 1000) {
        throw new Error('Time range cannot exceed 24 hours');
    }
    if (end.getTime() < start.getTime()) {
        throw new Error('endTime must be after startTime');
    }

    // Sanitize context
    const sanitizedContext = sanitizeString(context, 500);

    // Get data within range
    const activities = await getActivitiesRange(startTime, endTime, userId, env);
    const transcripts = await getTranscriptsRange(startTime, endTime, userId, env);

    // Get AI config from request headers
    const aiConfig = getAIConfigFromRequest(request);
    
    if (!aiConfig?.openRouterKey) {
        throw new Error('OpenRouter API key not provided. Configure it in Settings.');
    }

    // Generate specialized note
    const { content, title } = await generateMeetingNoteWithAI(activities, transcripts, sanitizedContext, startTime, env, aiConfig);

    // Format filename safe string
    const dateStr = new Date(startTime).toISOString().split('T')[0];
    const safeTitle = title.replace(/[^a-zA-Z0-9_\-\s]/g, '').trim();
    const filename = `Meetings/${dateStr} - ${safeTitle}.md`;

    return { success: true, note: content, filename };
}

// Get all possible local dates that could contain data for a time range
// This accounts for timezone differences (e.g., UTC query might span 2 local dates)
function getPossibleLocalDates(startMs: number, endMs: number): string[] {
    const dates = new Set<string>();
    
    // Add dates for UTC interpretation
    dates.add(new Date(startMs).toISOString().slice(0, 10));
    dates.add(new Date(endMs).toISOString().slice(0, 10));
    
    // Add dates for common timezone offsets (-12h to +14h from UTC)
    for (let offsetHours = -12; offsetHours <= 14; offsetHours += 6) {
        const offsetMs = offsetHours * 60 * 60 * 1000;
        dates.add(new Date(startMs + offsetMs).toISOString().slice(0, 10));
        dates.add(new Date(endMs + offsetMs).toISOString().slice(0, 10));
    }
    
    return Array.from(dates);
}

async function getActivitiesRange(start: string, end: string, userId: string, env: Env): Promise<Activity[]> {
    const startDate = new Date(start);
    const endDate = new Date(end);
    const startMs = startDate.getTime();
    const endMs = endDate.getTime();
    
    // Get all possible local dates that could contain relevant data
    const possibleDates = getPossibleLocalDates(startMs, endMs);
    
    // Build query with all possible dates
    const placeholders = possibleDates.map(() => '?').join(', ');
    const result = await env.DB.prepare(`
        SELECT * FROM activities 
        WHERE user_id = ? 
        AND (local_date IN (${placeholders}) OR local_date IS NULL)
        ORDER BY timestamp ASC
    `).bind(userId, ...possibleDates).all();
    
    // Filter by exact time range in code (handles timezone correctly using epoch ms)
    const activities = (result.results || []) as unknown as Activity[];
    return activities.filter(a => {
        const activityMs = new Date(a.timestamp).getTime();
        return activityMs >= startMs && activityMs <= endMs;
    });
}

async function getTranscriptsRange(start: string, end: string, userId: string, env: Env): Promise<Transcript[]> {
    const startDate = new Date(start);
    const endDate = new Date(end);
    const startMs = startDate.getTime();
    const endMs = endDate.getTime();
    
    // Get all possible local dates that could contain relevant data
    const possibleDates = getPossibleLocalDates(startMs, endMs);
    
    // Build query with all possible dates
    const placeholders = possibleDates.map(() => '?').join(', ');
    const result = await env.DB.prepare(`
        SELECT * FROM transcripts 
        WHERE user_id = ? 
        AND (local_date IN (${placeholders}) OR local_date IS NULL)
        ORDER BY timestamp ASC
    `).bind(userId, ...possibleDates).all();
    
    // Filter by exact time range in code (handles timezone correctly using epoch ms)
    const transcripts = (result.results || []) as unknown as Transcript[];
    return transcripts.filter(t => {
        const transcriptMs = new Date(t.timestamp).getTime();
        return transcriptMs >= startMs && transcriptMs <= endMs;
    });
}

// Generate a quick note for a specific time range (last X minutes)
export async function handleGenerateQuickNote(
    payload: { 
        minutesBack: number; 
        timezoneOffset?: number;  // Minutes from UTC (e.g., -180 for GMT-3)
        localTime?: string;       // Current local time "HH:mm"
        localDate?: string;       // Current local date "yyyy-MM-dd"
    },
    userId: string,
    env: Env,
    request: Request
): Promise<{ success: boolean; note: string; title: string }> {
    const { minutesBack, timezoneOffset, localTime, localDate } = payload;

    // Validate minutesBack (1 to 1440 minutes = 24 hours max)
    if (!minutesBack || minutesBack < 1 || minutesBack > 1440) {
        throw new Error('minutesBack must be between 1 and 1440');
    }

    const now = new Date();
    const startTime = new Date(now.getTime() - minutesBack * 60 * 1000);
    
    const endTimeStr = now.toISOString();
    const startTimeStr = startTime.toISOString();

    // Get data within range
    const activities = await getActivitiesRange(startTimeStr, endTimeStr, userId, env);
    const transcripts = await getTranscriptsRange(startTimeStr, endTimeStr, userId, env);

    if (activities.length === 0 && transcripts.length === 0) {
        return { success: false, note: '', title: '' };
    }

    // Get AI config from request headers
    const aiConfig = getAIConfigFromRequest(request);
    
    if (!aiConfig?.openRouterKey) {
        throw new Error('OpenRouter API key not provided. Configure it in Settings.');
    }

    // Generate note with AI - pass client timezone info
    const { content, title } = await generateQuickNoteWithAI(
        activities, 
        transcripts, 
        minutesBack, 
        startTimeStr, 
        endTimeStr, 
        env, 
        aiConfig,
        {
            timezoneOffset: timezoneOffset ?? 0,
            localTime: localTime ?? '',
            localDate: localDate ?? ''
        }
    );

    return { success: true, note: content, title };
}

// Extract timezone offset in minutes from activity timestamps
function extractTimezoneOffset(activities: Activity[], transcripts: Transcript[] = []): number {
    // Try activities first
    for (const activity of activities) {
        const tzMatch = activity.timestamp.match(/([+-])(\d{2}):(\d{2})$/);
        if (tzMatch) {
            const sign = tzMatch[1] === '+' ? 1 : -1;
            const tzHours = parseInt(tzMatch[2], 10);
            const tzMins = parseInt(tzMatch[3], 10);
            return sign * (tzHours * 60 + tzMins);
        }
    }
    
    // Try transcripts if no activities have timezone
    for (const transcript of transcripts) {
        const tzMatch = transcript.timestamp.match(/([+-])(\d{2}):(\d{2})$/);
        if (tzMatch) {
            const sign = tzMatch[1] === '+' ? 1 : -1;
            const tzHours = parseInt(tzMatch[2], 10);
            const tzMins = parseInt(tzMatch[3], 10);
            return sign * (tzHours * 60 + tzMins);
        }
    }
    
    return 0; // Default to UTC
}

// Helper to format time in user's local timezone
function formatLocalTime(date: Date, offsetMinutes: number): { dateStr: string; timeStr: string } {
    // Apply offset to get local time
    const localTime = new Date(date.getTime() + offsetMinutes * 60 * 1000);
    
    return {
        dateStr: localTime.toISOString().slice(0, 10),
        timeStr: localTime.toISOString().slice(11, 16)
    };
}

// AI function for quick notes
async function generateQuickNoteWithAI(
    activities: Activity[],
    transcripts: Transcript[],
    minutesBack: number,
    startTime: string,
    endTime: string,
    env: Env,
    aiConfig: { provider: string; openRouterKey: string; model: string; language: string },
    clientTimezone: { timezoneOffset: number; localTime: string; localDate: string }
): Promise<{ content: string; title: string }> {
    // Extract content
    const titles = [...new Set(activities.map(a => a.window_title).filter(Boolean))];
    const ocrContent = activities.map(a => a.ocr_text).filter(Boolean).join('\n');
    const transcriptText = transcripts.map(t => t.text).filter(Boolean).join('\n');

    // Use client timezone if provided, otherwise fallback to extracting from activities
    let tzOffsetMinutes = clientTimezone.timezoneOffset;
    if (tzOffsetMinutes === 0 && !clientTimezone.localTime) {
        tzOffsetMinutes = extractTimezoneOffset(activities, transcripts);
    }
    
    // Format times in user's local timezone
    const startDate = new Date(startTime);
    const endDate = new Date(endTime);
    const startLocal = formatLocalTime(startDate, tzOffsetMinutes);
    const endLocal = formatLocalTime(endDate, tzOffsetMinutes);
    
    // Use client's local time/date if provided (most accurate)
    let generatedAt: string;
    let dateStr: string;
    if (clientTimezone.localTime && clientTimezone.localDate) {
        generatedAt = `${clientTimezone.localDate} ${clientTimezone.localTime}`;
        dateStr = clientTimezone.localDate;
    } else {
        const nowLocal = formatLocalTime(new Date(), tzOffsetMinutes);
        generatedAt = `${nowLocal.dateStr} ${nowLocal.timeStr}`;
        dateStr = startLocal.dateStr;
    }
    
    const timeRange = `${startLocal.timeStr} - ${endLocal.timeStr}`;

    const prompt = aiConfig.language === 'pt'
        ? buildPortugueseQuickNotePrompt(dateStr, timeRange, minutesBack, titles, ocrContent, transcriptText, generatedAt)
        : buildEnglishQuickNotePrompt(dateStr, timeRange, minutesBack, titles, ocrContent, transcriptText, generatedAt);

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${aiConfig.openRouterKey}`,
        },
        body: JSON.stringify({
            model: aiConfig.model,
            messages: [{ role: 'user', content: prompt }],
            temperature: 0.7,
            max_tokens: 2048,
        }),
    });

    if (!response.ok) {
        throw new Error(`OpenRouter error: ${response.status}`);
    }

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content || '';
    
    // Extract title from the generated note (first H1)
    const titleMatch = content.match(/^#\s+(.+)$/m);
    let title = titleMatch ? titleMatch[1].trim() : '';
    
    // Clean title for filename
    title = title
        .replace(/[<>:"/\\|?*]/g, '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 100);
    
    // Fallback title
    if (!title) {
        title = aiConfig.language === 'pt' 
            ? `Nota ${dateStr} ${timeRange}` 
            : `Note ${dateStr} ${timeRange}`;
    }

    return { content, title };
}

function buildEnglishQuickNotePrompt(
    date: string,
    timeRange: string,
    minutesBack: number,
    titles: string[],
    ocrContent: string,
    transcripts: string,
    generatedAt: string
): string {
    return `Generate a detailed note for the last ${minutesBack} minutes (${date} ${timeRange}).

## Activity Data

### Window Titles
${titles.join('\n') || 'None'}

### Screen Content (Note: May contain OCR errors - interpret intelligently)
${ocrContent || 'None'}

### Audio/Conversations
${transcripts || 'None'}

---

## Instructions

Create a Markdown note with:

1. **Title (H1)**: A descriptive title based on the MAIN subject/topic of this period. Examples:
   - "Debugging Authentication Flow"
   - "Code Review Session"
   - "Research on React Patterns"
   The title should reflect what was predominantly done.

2. **Subtitle**: Right after the title, add: *Generated: ${generatedAt} | Period: ${timeRange}*

3. **Summary**: 2-4 paragraphs describing what was done during this period. Be detailed and specific.

4. **Key Points**: If relevant, add a bullet list of key findings, decisions, or tasks completed.

5. **Tags**: Add relevant #tags based on the content

## Rules
- ZERO EMOJIS
- Title must be descriptive of the main activity
- Be specific and detailed - capture important context
- Fix OCR errors intelligently
- Output only the Markdown note, no conversation`;
}

function buildPortugueseQuickNotePrompt(
    date: string,
    timeRange: string,
    minutesBack: number,
    titles: string[],
    ocrContent: string,
    transcripts: string,
    generatedAt: string
): string {
    return `Gere uma nota detalhada para os ultimos ${minutesBack} minutos (${date} ${timeRange}).

## Dados de Atividade

### Titulos das Janelas
${titles.join('\n') || 'Nenhum'}

### Conteudo da Tela (Nota: Pode conter erros de OCR - interprete inteligentemente)
${ocrContent || 'Nenhum'}

### Audio/Conversas
${transcripts || 'Nenhum'}

---

## Instrucoes

Crie uma nota Markdown com:

1. **Titulo (H1)**: Um titulo descritivo baseado no ASSUNTO PRINCIPAL deste periodo. Exemplos:
   - "Debugando Fluxo de Autenticacao"
   - "Sessao de Code Review"
   - "Pesquisa sobre Padroes React"
   O titulo deve refletir o que foi predominantemente feito.

2. **Subtitulo**: Logo apos o titulo, adicione: *Gerado em: ${generatedAt} | Periodo: ${timeRange}*

3. **Resumo**: 2-4 paragrafos descrevendo o que foi feito durante este periodo. Seja detalhado e especifico.

4. **Pontos Chave**: Se relevante, adicione uma lista de pontos chave, decisoes ou tarefas completadas.

5. **Tags**: Adicione #tags relevantes baseadas no conteudo

## Regras
- ZERO EMOJIS
- Titulo deve ser descritivo da atividade principal
- Seja especifico e detalhado - capture contexto importante
- Corrija erros de OCR inteligentemente
- Retorne apenas a nota Markdown, sem conversacao`;
}
