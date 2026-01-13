import { Env, UserConfig, CaptureMode } from '../types';

const DEFAULT_CONFIG: UserConfig = {
    obsidian_vault_path: '~/Documents/Obsidian',
    capture_modes: {
        'com.google.Chrome': 'full',
        'com.apple.Safari': 'full',
        'com.microsoft.VSCode': 'screenshot',
        'us.zoom.xos': 'audio',
        'com.apple.FaceTime': 'audio',
        'com.spotify.client': 'audio',
        'com.apple.finder': 'metadata',
        'com.1password.1password': 'ignore',
        'com.apple.systempreferences': 'ignore',
    },
    url_patterns: {
        'youtube.com': 'audio',
        'netflix.com': 'audio',
        'figma.com': 'screenshot',
        'notion.so': 'full',
        'bank*.com': 'ignore',
    },
    default_mode: 'metadata',
};

export async function handleGetConfig(
    userId: string,
    env: Env
): Promise<{ config: UserConfig }> {
    const stored = await env.CONFIG.get(`config:${userId}`);

    if (stored) {
        return { config: JSON.parse(stored) };
    }

    return { config: DEFAULT_CONFIG };
}

export async function handleUpdateConfig(
    config: Partial<UserConfig>,
    userId: string,
    env: Env
): Promise<{ success: boolean; config: UserConfig }> {
    const { config: existing } = await handleGetConfig(userId, env);

    const merged: UserConfig = {
        ...existing,
        ...config,
        capture_modes: {
            ...existing.capture_modes,
            ...(config.capture_modes || {}),
        },
        url_patterns: {
            ...existing.url_patterns,
            ...(config.url_patterns || {}),
        },
    };

    await env.CONFIG.put(`config:${userId}`, JSON.stringify(merged));

    return { success: true, config: merged };
}
