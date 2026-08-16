import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Inline bots (@bot query) and Mini Apps (Web Apps). Result parsing stays with
// the caller so it can decide how much of each result type to render.

export interface InlineResultRow {
  resultId: string;
  title: string;
  description: string;
  thumbFileId: number;
  thumbPath: string;
  kind: string; // 'article' | 'photo' | 'sticker' | 'animation' | 'other'
}

export interface InlineQueryPage {
  queryId: string;
  rows: InlineResultRow[];
}

function thumbFileIdOf(result: TdObject): number {
  const thumbnail = result['thumbnail'] as TdObject | undefined;
  if (thumbnail !== undefined) {
    const file = thumbnail['file'] as TdObject | undefined;
    return file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
  }
  // photo / sticker / animation results carry their own media object
  const media = (result['photo'] ?? result['sticker'] ?? result['animation']) as
    TdObject | undefined;
  if (media === undefined) { return 0; }
  const nested = media['thumbnail'] as TdObject | undefined;
  const nestedFile = nested !== undefined ? (nested['file'] as TdObject | undefined) : undefined;
  if (nestedFile !== undefined) { return (nestedFile['id'] as number | undefined) ?? 0; }
  const sizes = media['sizes'] as TdObject[] | undefined;
  if (sizes !== undefined && sizes.length > 0) {
    const smallest = sizes[0]['photo'] as TdObject | undefined;
    return smallest !== undefined ? ((smallest['id'] as number | undefined) ?? 0) : 0;
  }
  return 0;
}

function rowOf(result: TdObject): InlineResultRow | null {
  const typeName = (result['@type'] as string | undefined) ?? '';
  const id = (result['id'] as string | undefined) ?? '';
  if (id === '') { return null; }
  let kind = 'other';
  if (typeName === 'inlineQueryResultArticle') { kind = 'article'; }
  else if (typeName === 'inlineQueryResultPhoto') { kind = 'photo'; }
  else if (typeName === 'inlineQueryResultSticker') { kind = 'sticker'; }
  else if (typeName === 'inlineQueryResultAnimation') { kind = 'animation'; }
  return {
    resultId: id,
    title: (result['title'] as string | undefined) ?? '',
    description: (result['description'] as string | undefined) ?? '',
    thumbFileId: thumbFileIdOf(result),
    thumbPath: '',
    kind
  };
}

export async function getInlineResults(
  botUserId: number, chatId: number, query: string
): Promise<InlineQueryPage> {
  const request: TdRequest = { '@type': 'getInlineQueryResults' };
  request['bot_user_id'] = botUserId;
  request['chat_id'] = chatId;
  request['query'] = query;
  request['offset'] = '';
  const result = await getTdClient().send(request, 15000);
  const rows: InlineResultRow[] = [];
  for (const raw of (result['results'] as TdObject[] | undefined) ?? []) {
    const row = rowOf(raw);
    if (row !== null) { rows.push(row); }
  }
  return { queryId: `${result['inline_query_id'] ?? ''}`, rows };
}

export async function sendInlineResult(
  chatId: number, queryId: string, resultId: string, replyToId: number
): Promise<void> {
  const request: TdRequest = { '@type': 'sendInlineQueryResultMessage' };
  request['chat_id'] = chatId;
  request['query_id'] = queryId;
  request['result_id'] = resultId;
  request['hide_via_bot'] = false;
  if (replyToId !== 0) {
    const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
    replyTo['message_id'] = replyToId;
    request['reply_to'] = replyTo;
  }
  await getTdClient().send(request, 20000);
}

// --- Mini Apps (Web Apps) ---

function openParameters(): TdObject {
  const parameters: TdObject = { '@type': 'webAppOpenParameters' };
  // Reported to the bot's Mini App as the host client. A literal rather than
  // the resource because it identifies the client to a remote party and must
  // not change with the UI language.
  parameters['application_name'] = 'Petrelgram';
  return parameters;
}

// Resolves the https URL to load for a bot's Mini App; the caller opens it in
// the in-app browser.
export async function openMiniApp(
  chatId: number, botUserId: number, url: string
): Promise<string> {
  const request: TdRequest = { '@type': 'openWebApp' };
  request['chat_id'] = chatId;
  request['bot_user_id'] = botUserId;
  request['url'] = url;
  request['parameters'] = openParameters();
  const info = await getTdClient().send(request, 20000);
  return (info['url'] as string | undefined) ?? '';
}

export async function getMainMiniApp(chatId: number, botUserId: number): Promise<string> {
  const request: TdRequest = { '@type': 'getMainWebApp' };
  request['chat_id'] = chatId;
  request['bot_user_id'] = botUserId;
  request['start_parameter'] = '';
  request['parameters'] = openParameters();
  const info = await getTdClient().send(request, 20000);
  return (info['url'] as string | undefined) ?? '';
}

// Mini App reached through a t.me/<bot>/<app> link.
export async function getMiniAppLinkUrl(
  chatId: number, botUserId: number, shortName: string, startParameter: string
): Promise<string> {
  const request: TdRequest = { '@type': 'getWebAppLinkUrl' };
  request['chat_id'] = chatId;
  request['bot_user_id'] = botUserId;
  request['web_app_short_name'] = shortName;
  request['start_parameter'] = startParameter;
  request['allow_write_access'] = false;
  request['parameters'] = openParameters();
  const result = await getTdClient().send(request, 20000);
  return (result['url'] as string | undefined) ?? '';
}

export function closeMiniApp(launchId: string): void {
  if (launchId === '') { return; }
  const request: TdRequest = { '@type': 'closeWebApp' };
  request['web_app_launch_id'] = launchId;
  getTdClient().send(request).catch((): void => {});
}

// A bot's Mini App button URL from its userFullInfo (0 = none).
export async function botMiniAppUrl(botUserId: number): Promise<string> {
  const request: TdRequest = { '@type': 'getUserFullInfo' };
  request['user_id'] = botUserId;
  const info = await getTdClient().send(request, 12000);
  const botInfo = info['bot_info'] as TdObject | undefined;
  if (botInfo === undefined) { return ''; }
  const menuButton = botInfo['menu_button'] as TdObject | undefined;
  return menuButton !== undefined ? ((menuButton['url'] as string | undefined) ?? '') : '';
}
