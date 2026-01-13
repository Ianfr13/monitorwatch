/**
 * MonitorWatch API - Main Router
 * 
 * Security Features:
 * - API Key authentication (constant-time comparison)
 * - Rate limiting per IP
 * - Input validation
 * - Sanitized error responses
 */

import { Env, ActivityPayload, TranscriptPayload, GenerateNoteRequest, UserConfig } from './types';
import { handleActivity } from './handlers/activity';
import { handleTranscript } from './handlers/transcript';
import { handleGenerateNote, handleGetNote, handleGenerateMeetingNote } from './handlers/notes';
import { handleGetConfig, handleUpdateConfig } from './handlers/config';
import { handleTranscribe } from './handlers/transcribe';
import { handleVision } from './handlers/vision';

// Rate limiting: Max requests per IP per minute
const RATE_LIMIT = 60;
const RATE_WINDOW_MS = 60_000;
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(ip: string): boolean {
    const now = Date.now();
    const record = rateLimitMap.get(ip);
    
    if (!record || now > record.resetAt) {
        rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
        return true;
    }
    
    if (record.count >= RATE_LIMIT) {
        return false;
    }
    
    record.count++;
    return true;
}

// Constant-time string comparison to prevent timing attacks
function secureCompare(a: string, b: string): boolean {
    if (a.length !== b.length) {
        // Still do a dummy comparison to maintain constant time
        let result = 0;
        for (let i = 0; i < a.length; i++) {
            result |= a.charCodeAt(i) ^ a.charCodeAt(i);
        }
        return false;
    }
    
    let result = 0;
    for (let i = 0; i < a.length; i++) {
        result |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return result === 0;
}

// Validate user_id format (alphanumeric, dashes, underscores only)
function isValidUserId(userId: string): boolean {
    return /^[a-zA-Z0-9_-]{1,64}$/.test(userId);
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);
        const path = url.pathname;
        const method = request.method;

        // Get client IP for rate limiting
        const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';

        // CORS headers - restrict to specific origins in production
        const corsHeaders = {
            'Access-Control-Allow-Origin': '*', // In production, set to your app's domain
            'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-OpenRouter-Key, X-Note-Language, X-User-ID',
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': 'DENY',
        };

        // Handle preflight
        if (method === 'OPTIONS') {
            return new Response(null, { headers: corsHeaders });
        }

        // Rate limiting check
        if (!checkRateLimit(clientIP)) {
            return Response.json(
                { error: 'Too Many Requests' },
                { status: 429, headers: { ...corsHeaders, 'Retry-After': '60' } }
            );
        }

        // Auth check with constant-time comparison
        const authHeader = request.headers.get('Authorization');
        const apiKey = authHeader?.replace('Bearer ', '') || '';

        if (!secureCompare(apiKey, env.API_SECRET_KEY)) {
            // Add small delay to prevent timing attacks on failed auth
            await new Promise(resolve => setTimeout(resolve, 100));
            return Response.json(
                { error: 'Unauthorized' },
                { status: 401, headers: corsHeaders }
            );
        }

        // Extract and validate user_id
        const rawUserId = request.headers.get('X-User-ID') || 'default';
        const userId = isValidUserId(rawUserId) ? rawUserId : 'default';

        try {
            // POST /api/activity - Store activity event
            if (path === '/api/activity' && method === 'POST') {
                const payload: ActivityPayload = await request.json();
                const result = await handleActivity(payload, userId, env);
                return Response.json(result, { headers: corsHeaders });
            }

            // POST /api/transcript - Store audio transcript
            if (path === '/api/transcript' && method === 'POST') {
                const payload: TranscriptPayload = await request.json();
                const result = await handleTranscript(payload, userId, env);
                return Response.json(result, { headers: corsHeaders });
            }

            // POST /api/transcribe - Transcribe audio via OpenRouter
            if (path === '/api/transcribe' && method === 'POST') {
                const result = await handleTranscribe(request, userId, env);
                return result;
            }

            // POST /api/vision - Analyze image via OpenRouter
            if (path === '/api/vision' && method === 'POST') {
                const result = await handleVision(request, userId, env);
                return result;
            }

            // POST /api/notes/meeting - Generate Meeting Minutes
            if (path === '/api/notes/meeting' && method === 'POST') {
                const payload = await request.json() as any;
                const result = await handleGenerateMeetingNote(payload, userId, env, request);
                return Response.json(result, { headers: corsHeaders });
            }

            // POST /api/notes/generate - Generate note for a date
            if (path === '/api/notes/generate' && method === 'POST') {
                const payload: GenerateNoteRequest = await request.json();
                const result = await handleGenerateNote(payload, userId, env, request);
                return Response.json(result, { headers: corsHeaders });
            }

            // GET /api/notes/:date - Get note for a date
            if (path.startsWith('/api/notes/') && method === 'GET') {
                const date = path.split('/').pop()!;
                const result = await handleGetNote(date, userId, env);
                return Response.json(result, { headers: corsHeaders });
            }

            // GET /api/config - Get user config
            if (path === '/api/config' && method === 'GET') {
                const result = await handleGetConfig(userId, env);
                return Response.json(result, { headers: corsHeaders });
            }

            // PUT /api/config - Update user config
            if (path === '/api/config' && method === 'PUT') {
                const config = await request.json() as Partial<UserConfig>;
                const result = await handleUpdateConfig(config, userId, env);
                return Response.json(result, { headers: corsHeaders });
            }

            // 404
            return Response.json(
                { error: 'Not Found' },
                { status: 404, headers: corsHeaders }
            );

        } catch (error) {
            // Log full error internally, but don't expose details to client
            console.error('API Error:', error);
            return Response.json(
                { error: 'Internal Server Error' },
                { status: 500, headers: corsHeaders }
            );
        }
    },

    // Scheduled Event (Cron) - Cleanup Database
    async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
        console.log(`[Cron] Starting daily cleanup: ${new Date().toISOString()}`);

        try {
            // Retention Policy: Ephemeral / Zero-Retention
            // We only keep data for 24 hours to allow for:
            // 1. End-of-day syncing
            // 2. Next-morning syncing (for yesterday's data)
            // After that, it is assumed to be in Obsidian (User responsibility).

            const retentionDate = new Date();
            retentionDate.setDate(retentionDate.getDate() - 1); // Keep only last 24h
            const cutoff = retentionDate.toISOString();

            // Prune Activities
            const resultActivity = await env.DB.prepare(
                `DELETE FROM activities WHERE timestamp < ?`
            ).bind(cutoff).run();

            // Prune Transcripts
            const resultTranscript = await env.DB.prepare(
                `DELETE FROM transcripts WHERE timestamp < ?`
            ).bind(cutoff).run();

            // Prune Notes (New: User manages storage in Obsidian)
            // We assume note is generated and synced within 24h of creation.
            // Using updated_at to ensure we don't delete something currently being worked on.
            const resultNotes = await env.DB.prepare(
                `DELETE FROM notes WHERE updated_at < ?`
            ).bind(cutoff).run();

            console.log(`[Cron] Cleanup complete.`);
            console.log(`- Deleted Activities: ${resultActivity.meta.changes}`);
            console.log(`- Deleted Transcripts: ${resultTranscript.meta.changes}`);
            console.log(`- Deleted Notes: ${resultNotes.meta.changes}`);

        } catch (error) {
            console.error('[Cron] Cleanup failed:', error);
        }
    },
};
